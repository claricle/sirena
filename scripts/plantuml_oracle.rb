# frozen_string_literal: true

# PlantUML oracle: decides whether the pinned PlantUML binary accepts a source.
# The contract is written down in
# TODO.foundation/12-plantuml-oracle-contract.md.
#
# Usage: ruby scripts/plantuml_oracle.rb --write OUT.yml CASES_DIR
#   CASES_DIR  directory of *.puml files; the case id is the path below it
#              without the extension
#   --write    verdict file to replace, all-or-nothing
#
# Three states, and only two of them are verdicts:
#   :valid           the binary rendered a diagram
#   :rejected        the binary refused the source (an error image, exit 200)
#   :infrastructure  the oracle could not judge (missing Java or Graphviz, OOM,
#                    timeout, unreadable output). NEVER recorded as a verdict.

require "digest"
require "open3"
require "rexml/document"
require "time"
require "yaml"

module PlantumlOracle
  CONTRACT_VERSION = 1
  DEFAULT_BINARY = "plantuml"
  DEFAULT_TIMEOUT = 60
  KILL_GRACE = 2

  # `--pipe` reads the source on stdin and writes the SVG on stdout. Measured
  # on 1.2026.6: a syntax error exits 200 (stderr "ERROR\n<line>\n<message>")
  # and still writes an SVG, an error image with no data-diagram-type.
  ARGUMENTS = %w[--svg --pipe --charset UTF-8].freeze
  EXIT_VALID = 0
  EXIT_REJECTED = 200

  # Present on the root of every diagram PlantUML renders; absent on its error
  # image. This, not the exit code, is what tells the two apart.
  DIAGRAM_TYPE = "data-diagram-type"
  ERROR_TEXT =
    /Syntax Error|Error line \d|cannot include|An error has occurred/i
  # Java or the OS failing underneath PlantUML, not PlantUML judging the source.
  INFRASTRUCTURE_STDERR = /
    OutOfMemoryError|StackOverflowError|Exception in thread|java\.lang\.|
    java\.io\.IOException|Cannot run program|Cannot find Graphviz|
    Unable to access jarfile|command not found
  /x

  CANARY_VALID = "@startuml\nA -> B : hi\n@enduml\n"
  CANARY_INVALID = "@startuml\nclass A {\n@enduml\n"

  Execution = Struct.new(:status, :stdout, :stderr, :timed_out, :spawn_error,
                         keyword_init: true)
  Result = Struct.new(:state, :reason, :svg, keyword_init: true) do
    def verdict? = %i[valid rejected].include?(state)
  end

  class CanaryFailure < StandardError; end
  class InfrastructureFailure < StandardError; end

  # The only code that touches a process. Everything else takes a runner so
  # specs can stub this boundary.
  module Runner
    module_function

    def call(command, input, timeout)
      Open3.popen3(*command, pgroup: true) do |stdin, out, err, waiter|
        writer = Thread.new { feed(stdin, input) }
        readers = [out, err].map { |io| Thread.new { io.read } }
        next killed(waiter) unless waiter.join(timeout)

        finished(waiter, [writer, *readers])
      end
    rescue SystemCallError => e
      Execution.new(status: nil, stdout: "", stderr: "", spawn_error: e.message)
    end

    def killed(waiter)
      kill_group(waiter)
      Execution.new(status: nil, stdout: "", stderr: "", timed_out: true)
    end

    def finished(waiter, threads)
      threads.each(&:join)
      stdout, stderr = threads.drop(1).map(&:value)
      Execution.new(status: waiter.value.exitstatus, stdout: stdout,
                    stderr: stderr, timed_out: false)
    end

    def feed(stdin, input)
      stdin.write(input)
    rescue Errno::EPIPE
      nil
    ensure
      stdin.close unless stdin.closed?
    end

    # The whole process group, so a wrapper script cannot leave its java child
    # running. TERM first, KILL if it is still there after the grace period.
    def kill_group(waiter)
      Process.kill("TERM", -waiter.pid)
      return if waiter.join(KILL_GRACE)

      Process.kill("KILL", -waiter.pid)
      waiter.join
    rescue Errno::ESRCH
      nil
    end
  end

  module_function

  def command(binary = DEFAULT_BINARY)
    [binary, *ARGUMENTS]
  end

  # source -> Result. The runner is called as
  # runner.call(command, input, timeout).
  def judge(source, binary: DEFAULT_BINARY, timeout: DEFAULT_TIMEOUT,
            runner: Runner)
    classify(runner.call(command(binary), source, timeout))
  end

  def classify(run)
    process_failure(run) || output_failure(run) || classify_svg(run)
  end

  def process_failure(run)
    return infra("spawn failed: #{run.spawn_error}") if run.spawn_error
    return infra("timed out and was killed") if run.timed_out

    infra("killed by a signal") if run.status.nil?
  end

  def output_failure(run)
    if run.stderr.match?(INFRASTRUCTURE_STDERR)
      return infra("java or graphviz failure: " \
                   "#{run.stderr[INFRASTRUCTURE_STDERR]}")
    end

    infra("unexpected exit #{run.status}") unless
      [EXIT_VALID, EXIT_REJECTED].include?(run.status)
  end

  def classify_svg(run)
    root = svg_root(run.stdout)
    unless root
      return infra("no well-formed svg on stdout (exit #{run.status})")
    end

    if root.attributes.key?(DIAGRAM_TYPE)
      rendered(run, root)
    else
      unrendered(run)
    end
  end

  def rendered(run, root)
    unless run.status == EXIT_VALID
      return infra("exit #{run.status} with a rendered diagram")
    end

    Result.new(state: :valid, svg: run.stdout,
               reason: "rendered #{root.attributes[DIAGRAM_TYPE]}")
  end

  def unrendered(run)
    rejected = run.status == EXIT_REJECTED || error_text?(run.stdout)
    return rejected(run) if rejected

    infra("exit 0 with an svg that is neither a diagram " \
          "nor a recognised error image")
  end

  def rejected(run)
    Result.new(state: :rejected, reason: run.stderr.lines.last.to_s.strip,
               svg: run.stdout)
  end

  def error_text?(svg)
    svg.match?(ERROR_TEXT)
  end

  def svg_root(text)
    root = REXML::Document.new(text).root
    root if root&.name == "svg"
  rescue REXML::ParseException
    nil
  end

  def infra(reason)
    Result.new(state: :infrastructure, reason: reason)
  end

  # Raises CanaryFailure unless the oracle is alive in both directions: it
  # renders a good source and refuses a bad one. A refresh may not start
  # without this.
  def canary!(**)
    good = judge(CANARY_VALID, **)
    unless good.state == :valid
      raise CanaryFailure,
            "valid canary came back #{good.state}: #{good.reason}"
    end

    bad = judge(CANARY_INVALID, **)
    return if bad.state == :rejected

    raise CanaryFailure, "invalid canary came back #{bad.state}: #{bad.reason}"
  end

  # Versions of everything the verdict depends on. A probe that cannot run is
  # an infrastructure failure, so a verdict never carries a blank version.
  def toolchain(binary: DEFAULT_BINARY, runner: Runner)
    {
      "plantuml" => probe(runner, [binary, "--version"],
                          /PlantUML version\s+(\S.*)/),
      "java" => probe(runner, ["java", "-version"], /version "([^"]+)"/),
      "graphviz" => probe(runner, ["dot", "-V"], /graphviz version\s+(\S+)/),
    }
  end

  def probe(runner, command, pattern)
    run = runner.call(command, "", 30)
    match = pattern.match("#{run.stdout}\n#{run.stderr}")
    unless match && !run.spawn_error && !run.timed_out
      raise InfrastructureFailure,
            "cannot read version from `#{command.join(' ')}`"
    end

    match[1].strip
  end

  def record(id, source, result, versions)
    { "id" => id, "verdict" => result.state.to_s, "reason" => result.reason }
      .merge(hashes(source, result),
             versions.slice("plantuml", "java", "graphviz"),
             "command" => command.join(" "), "contract" => CONTRACT_VERSION)
  end

  def hashes(source, result)
    {
      "source_sha256" => Digest::SHA256.hexdigest(source),
      "svg_sha256" => result.svg && Digest::SHA256.hexdigest(result.svg),
    }
  end

  # cases: { id => source }. Writes `path` only after every case has a verdict;
  # any infrastructure failure, failed canary or error leaves `path` untouched.
  # `options` are the judge's: binary:, timeout:, runner:.
  def refresh(cases, path, now: Time.now, **options)
    canary!(**options)
    versions = toolchain(**options.slice(:binary, :runner))
    records = verdict_records(cases, versions, **options)
    generated = { "generated_at" => now.utc.iso8601, "toolchain" => versions }
    write_atomically(path, generated.merge("verdicts" => records))
    records
  end

  def verdict_records(cases, versions, **options)
    cases.sort.map do |id, source|
      result = judge(source, **options)
      unless result.verdict?
        raise InfrastructureFailure, "#{id}: #{result.reason}"
      end

      record(id, source, result, versions)
    end
  end

  def write_atomically(path, document)
    temp = "#{path}.tmp#{Process.pid}"
    File.write(temp, YAML.dump(document))
    File.rename(temp, path)
  ensure
    File.delete(temp) if temp && File.exist?(temp)
  end

  def load_cases(dir)
    Dir.glob("**/*.puml", base: dir).sort.to_h do |file|
      source = File.read(File.join(dir, file), encoding: "UTF-8")
      [file.delete_suffix(".puml"), source]
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  args = ARGV.dup
  if args.include?("--write")
    out = args.delete_at(args.index("--write").to_i + 1)
  end
  args.delete("--write")
  dir = args.first
  abort "usage: plantuml_oracle.rb --write OUT.yml CASES_DIR" unless out && dir

  begin
    records = PlantumlOracle.refresh(PlantumlOracle.load_cases(dir), out)
    puts "wrote #{records.size} verdicts to #{out}"
  rescue PlantumlOracle::CanaryFailure,
         PlantumlOracle::InfrastructureFailure => e
    abort "NOT RUN, #{out} left untouched: #{e.message}"
  end
end
