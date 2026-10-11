# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "bundler"
require "open3"

# Records and compares what each public surface does for a list of cases, so
# a refactor can prove it changed neither. Each surface is compared to ITSELF
# across two checkouts, never the CLI to the API (the CLI adds a newline and
# an "Error: " prefix, so the two are never equal):
#
#   API: SVG checksum, or error class and exact error message
#   CLI: stdout checksum, stderr text, exit status
#
# Usage (run from the current checkout):
#   ruby scripts/surface_manifest.rb cases CORPUS_ROOT COUNT SHAPE_DIR OUT
#   ruby scripts/surface_manifest.rb record CHECKOUT_ROOT CASES_JSON OUT
#   ruby scripts/surface_manifest.rb compare BEFORE_JSON AFTER_JSON
module SurfaceManifest
  class ManifestError < StandardError; end

  SURFACES = %w[api_svg api_error cli_stdout cli_stderr cli_exit].freeze
  LAUNCHER = %w[bundle exec].freeze
  CASE_TIMEOUT = 20
  API_TIMEOUT = 1800
  TODAY = "2026-01-01"
  ROOT_MARK = "<ROOT>"
  # Object addresses differ on every run (Parslet::Position inspect, etc.).
  ADDRESS = /0x\h{8,16}/

  # Runs inside the checkout under test, so it must not reference this file.
  API_PROBE = <<~RUBY
    require "json"
    require "digest"
    require "timeout"
    require "date"
    require "sirena"
    today = Date.parse(ARGV.fetch(0))
    limit = Integer(ARGV.fetch(1))
    rows = JSON.parse($stdin.read).to_h do |kase|
      options = { today: today }.merge(
        (kase["api_options"] || {}).transform_keys(&:to_sym),
      )
      row =
        begin
          source = File.binread(kase.fetch("source_path"))
          svg = Timeout.timeout(limit) { Sirena.render(source, options) }
          { "svg_sha256" => Digest::SHA256.hexdigest(svg.to_s) }
        rescue Timeout::Error
          { "error_class" => "Timeout::Error", "error_message" => "timeout" }
        rescue StandardError, SystemStackError, NoMemoryError => e
          { "error_class" => e.class.name, "error_message" => e.message }
        end
      [kase.fetch("id"), row]
    end
    $stdout.write(JSON.generate(rows))
  RUBY

  module_function

  # Deterministic evenly spaced sample of *.mmd files under corpus_root.
  def sample_paths(corpus_root, count)
    paths = Dir.glob(File.join(corpus_root, "*", "*.mmd"))
    return paths if count >= paths.size

    step = paths.size.to_f / count
    Array.new(count) { |index| paths.fetch((index * step).floor) }.uniq
  end

  def sample_cases(corpus_root, count)
    sample_paths(corpus_root, count).map do |path|
      { "id" => path.delete_prefix("#{corpus_root}/"), "source_path" => path }
    end
  end

  # Fixed extra shapes: an unknown type, an empty file, a missing file and
  # CLI flag variants. They are built in shape_dir so both refs read them.
  def shape_cases(shape_dir, base_path)
    FileUtils.mkdir_p(shape_dir)
    unknown = write_shape(shape_dir, "unknown.mmd", "bogusDiagram\n  a --> b\n")
    empty = write_shape(shape_dir, "empty.mmd", "")
    [
      shape("shape/unknown-type", unknown),
      shape("shape/empty", empty),
      shape("shape/missing-file", File.join(shape_dir, "absent.mmd")),
      shape("shape/theme-dark", base_path, ["--theme", "dark"], "dark"),
      shape("shape/theme-unknown", base_path, ["--theme", "nope"], "nope"),
      shape("shape/verbose", base_path, ["--verbose"]),
      shape("shape/format-png", base_path, ["--format", "png"]),
    ]
  end

  def write_shape(dir, name, body)
    File.join(dir, name).tap { |path| File.write(path, body) }
  end

  def shape(id, path, cli_args = [], theme = nil)
    kase = { "id" => id, "source_path" => path, "cli_args" => cli_args }
    kase["api_options"] = { "theme" => theme } if theme
    kase
  end

  def build_cases(corpus_root, count, shape_dir)
    sampled = sample_cases(corpus_root, count)
    raise ManifestError, "no cases under #{corpus_root}" if sampled.empty?

    sampled + shape_cases(shape_dir, sampled.first.fetch("source_path"))
  end

  def load_cases(path)
    cases = JSON.parse(File.read(path))
    ids = cases.map { |kase| kase.fetch("id") }
    raise ManifestError, "duplicate case ids in #{path}" if ids.uniq != ids

    cases
  rescue JSON::ParserError, KeyError, NoMethodError => e
    raise ManifestError, "#{path} is not a valid case list: #{e.message}"
  end

  # Runs argv, killing its whole process group past the timeout.
  # The child must see ONLY its own checkout's Gemfile: an inherited
  # BUNDLE_GEMFILE or RUBYOPT from `bundle exec` loads the caller's lib too.
  def checkout_env(root)
    env = Bundler.unbundled_env
    (ENV.keys - env.keys).each { |key| env[key] = nil }
    env.merge(
      "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
    )
  end

  def run_process(argv, chdir:, timeout:, stdin_data: "")
    Open3.popen3(
      checkout_env(chdir), *argv, **process_options(chdir)
    ) do |stdin, *pipes, wait|
      feed(stdin, stdin_data)
      collect(pipes, wait, timeout)
    end
  end

  def process_options(chdir)
    Gem.win_platform? ? { chdir: chdir } : { chdir: chdir, pgroup: true }
  end

  def feed(stdin, data)
    stdin.write(data)
  rescue Errno::EPIPE
    nil
  ensure
    stdin.close
  end

  def collect(pipes, wait, timeout)
    readers = pipes.map { |io| Thread.new { io.binmode.read } }
    timed_out = wait.join(timeout).nil?
    Process.kill("KILL", kill_target(wait.pid)) if timed_out
    stdout, stderr = readers.map(&:value)
    { stdout: stdout, stderr: stderr, timed_out: timed_out,
      status: timed_out ? nil : wait.value.exitstatus }
  end

  def kill_target(pid)
    Gem.win_platform? ? pid : -pid
  end

  def scrub(text, root)
    clean = text.dup.force_encoding(Encoding::UTF_8).scrub
    clean.gsub("\r\n", "\n").gsub(root, ROOT_MARK).gsub(ADDRESS, "0xADDR")
  end

  def api_results(root, cases, launcher: LAUNCHER, timeout: API_TIMEOUT)
    result = run_process(api_argv(root, launcher), chdir: root,
                                                   timeout: timeout,
                                                   stdin_data: cases.to_json)
    unless !result[:timed_out] && result[:status]&.zero?
      raise ManifestError,
            "API probe failed in #{root}: #{scrub(result[:stderr], root)}"
    end

    JSON.parse(result[:stdout]).transform_values { |row| scrub_row(row, root) }
  end

  def api_argv(root, launcher)
    launcher + ["ruby", "-I", File.join(root, "lib"), "-e", API_PROBE,
                TODAY, CASE_TIMEOUT.to_s]
  end

  def scrub_row(row, root)
    message = row["error_message"]
    message ? row.merge("error_message" => scrub(message, root)) : row
  end

  def cli_result(root, kase, launcher: LAUNCHER, timeout: CASE_TIMEOUT)
    argv = launcher + ["ruby", "exe/sirena", "render",
                       kase.fetch("source_path"), *kase.fetch("cli_args", [])]
    result = run_process(argv, chdir: root, timeout: timeout)
    {
      "stdout_sha256" => Digest::SHA256.hexdigest(result[:stdout]),
      "stderr" => scrub(result[:stderr], root),
      "exit_status" => result[:timed_out] ? "timeout" : result[:status],
    }
  end

  def record(root, cases, launcher: LAUNCHER)
    api = api_results(root, cases, launcher: launcher)
    rows = cases.to_h do |kase|
      id = kase.fetch("id")
      [id, { "api" => api.fetch(id),
             "cli" => cli_result(root, kase, launcher: launcher) }]
    end
    { "root" => root, "cases" => rows }
  end

  # Returns [{ "case", "surface", "before", "after" }, ...].
  def compare(before, after)
    left = before.fetch("cases")
    right = after.fetch("cases")
    (left.keys | right.keys).sort.flat_map do |id|
      differences_for(id, left, right)
    end
  end

  def differences_for(id, left, right)
    return case_differences(id, left.fetch(id), right.fetch(id)) \
      if left.key?(id) && right.key?(id)

    [difference(id, "case_set", left.key?(id), right.key?(id))]
  end

  def case_differences(id, before, after)
    before_values = surface_values(before)
    after_values = surface_values(after)
    SURFACES.filter_map do |surface|
      next if before_values.fetch(surface) == after_values.fetch(surface)

      difference(id, surface, before_values.fetch(surface),
                 after_values.fetch(surface))
    end
  end

  def surface_values(row)
    api = row.fetch("api")
    cli = row.fetch("cli")
    {
      "api_svg" => api["svg_sha256"],
      "api_error" => [api["error_class"], api["error_message"]],
      "cli_stdout" => cli.fetch("stdout_sha256"),
      "cli_stderr" => cli.fetch("stderr"),
      "cli_exit" => cli.fetch("exit_status"),
    }
  end

  def difference(id, surface, before, after)
    { "case" => id, "surface" => surface, "before" => before, "after" => after }
  end

  def report(differences)
    differences.map do |diff|
      "DIFFERS #{diff['case']} [#{diff['surface']}]: " \
        "#{diff['before'].inspect[0, 160]} -> #{diff['after'].inspect[0, 160]}"
    end
  end

  def read_manifest(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError, Errno::ENOENT => e
    raise ManifestError, "#{path} is not a readable manifest: #{e.message}"
  end

  COMMANDS = { "cases" => :build_cases_file, "record" => :record_file,
               "compare" => :compare_files }.freeze

  # Returns [output_lines, success].
  def run(argv)
    command, *args = argv
    handler = COMMANDS[command]
    raise ManifestError, usage unless handler
    raise ManifestError, usage unless args.size == method(handler).arity

    result = public_send(handler, *args)
    result.is_a?(String) ? [[result], true] : result
  end

  def usage
    "usage: surface_manifest.rb cases CORPUS COUNT SHAPE_DIR OUT | " \
      "record ROOT CASES OUT | compare BEFORE AFTER"
  end

  def build_cases_file(corpus_root, count, shape_dir, out)
    cases = build_cases(File.expand_path(corpus_root), Integer(count),
                        File.expand_path(shape_dir))
    File.write(out, JSON.pretty_generate(cases))
    "wrote #{cases.size} cases to #{out}"
  end

  def record_file(root, cases_path, out)
    manifest = record(File.expand_path(root), load_cases(cases_path))
    File.write(out, JSON.pretty_generate(manifest))
    "recorded #{manifest.fetch('cases').size} cases from #{root} to #{out}"
  end

  def compare_files(before_path, after_path)
    differences = compare(read_manifest(before_path), read_manifest(after_path))
    return [["surfaces identical"], true] if differences.empty?

    [report(differences) << "#{differences.size} differences", false]
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    lines, success = SurfaceManifest.run(ARGV)
    puts lines
    exit(success ? 0 : 1)
  rescue SurfaceManifest::ManifestError => e
    warn e.message
    exit 2
  end
end
