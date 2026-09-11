# frozen_string_literal: true

# A task file and its helper module, not library code: lib/tasks/*.rake is
# loaded only by the Rakefile's `Dir.glob('lib/tasks/**/*.rake').each { |r|
# load r }`, never by lib/sirena.rb's require chain, so Sirena::Corpus's
# module-level `abort` in #check! can only ever run inside a rake process
# (a real script entry point) -- confirmed by grepping both files for any
# path that would `require` this one.
require "yaml"
require "json"
require "fileutils"
require "timeout"

# TODO.architecture/01-safety-net.md, Part B ("Corpus check"). `rake corpus`
# renders every spec/mermaid case through Sirena.render and writes
# scoreboard/corpus.json -- the corpus column of the ONE scoreboard
# TODO.foundation/02b's schema defines (per-case rows; an aggregate rate is
# always DERIVED from them, never stored as its own source of truth). `rake
# corpus:check` re-runs it and diffs against the committed file, so a
# regression -- or an unrecorded improvement -- fails the build instead of
# drifting silently.
#
# Deliberately NOT here, per TODO.architecture/DO-NOT-BUILD.md: pinning the
# oracle toolchain, regenerating reference SVGs, content-hash case IDs, or a
# geometry/conformance/coverage/lint-debt column. Those arrive with
# TODO.foundation/02b at item 08 step 3a.
module Sirena
  module Corpus
    CORPUS_ROOT = File.expand_path("../../spec/mermaid", __dir__)
    VERDICTS_PATH = File.join(CORPUS_ROOT, "corpus-verdicts.yml")
    SCOREBOARD_PATH = File.expand_path("../../scoreboard/corpus.json", __dir__)

    # A hung case is a failure, not a hang. Matches scripts/corpus_sweep.rb's
    # own budget.
    CASE_TIMEOUT = 10

    module_function

    def types
      Dir.children(CORPUS_ROOT)
        .select { |entry| File.directory?(File.join(CORPUS_ROOT, entry)) }
        .sort
    end

    # Every case, or one type's, as paths relative to CORPUS_ROOT -- the
    # same key shape spec/mermaid/corpus-verdicts.yml already uses.
    def cases(type)
      available = types
      selected = type ? [type] : available
      unknown = selected - available
      unless unknown.empty?
        raise "Unknown corpus type(s): #{unknown.join(', ')}. " \
              "Available: #{available.join(', ')}"
      end

      selected.flat_map do |t|
        Dir.glob(File.join(CORPUS_ROOT, t, "*.mmd")).map do |path|
          path.sub("#{CORPUS_ROOT}/", "")
        end
      end
    end

    # case path => oracle verdict (valid / invalid / artifact / unknown),
    # per scripts/corpus_verdicts.rb's own committed output. A case with no
    # row (should not happen; the file covers the whole corpus) reads as
    # "unknown" rather than raising, so a corpus addition mid-cycle degrades
    # to a wider denominator instead of crashing the rake task.
    def verdicts
      rows = YAML.load_file(VERDICTS_PATH)
      rows.to_h { |row| [row["case"], row["verdict"]] }
    end

    # Which pipeline stage an exception belongs to. Item 01 step 0 gave each
    # layer its own Sirena::Error subclass precisely so this is a lookup
    # instead of a guess.
    def stage_for(exception)
      case exception
      when Sirena::Engine::DiagramTypeError then "detect"
      when Sirena::Parser::ParseError then "parse"
      when Sirena::Transform::TransformError then "layout"
      when Sirena::Renderer::RenderError then "render"
      when Timeout::Error then "timeout"
      else "unknown"
      end
    end

    # One case, one render. Pass means Sirena.render did not raise -- not
    # that the SVG it returned is well-formed or conforming; that is item
    # 04's conformance column, out of scope here on purpose.
    def render_case(relative_path)
      source = File.read(File.join(CORPUS_ROOT, relative_path))
      Timeout.timeout(CASE_TIMEOUT) { Sirena::Engine.new.render(source) }
      { pass: true }
    rescue StandardError => e
      {
        pass: false,
        stage: stage_for(e),
        exception_class: e.class.name,
        # Console-only detail (never written to the committed scoreboard):
        # the first line, so a stray backtrace in a message can't leak into
        # a one-line failure report.
        message: e.message.to_s.each_line.first.to_s.chomp
      }
    end

    def run_cases(paths)
      paths.to_h { |path| [path, render_case(path)] }
    end

    # The committed row shape: case, oracle verdict, pass, and on failure
    # the stage + exception class. No aggregate counts live in the file --
    # every rate is derived from these rows on demand.
    def rows_for_scoreboard(results, verdict_by_case)
      results.map do |path, result|
        row = {
          "case" => path,
          "verdict" => verdict_by_case.fetch(path, "unknown"),
          "pass" => result[:pass]
        }
        unless result[:pass]
          row["stage"] = result[:stage]
          row["exception_class"] = result[:exception_class]
        end
        row
      end.sort_by { |row| row["case"] }
    end

    # Writes via a temp file + rename rather than File.write directly, so a
    # process killed mid-render (this runs after all 1997 cases finish, but
    # the write itself is not instant) can never leave scoreboard/corpus.json
    # truncated -- rename is atomic, an interrupted write just leaves the
    # temp file behind and the committed file untouched.
    def write_scoreboard(rows)
      FileUtils.mkdir_p(File.dirname(SCOREBOARD_PATH))
      tmp_path = "#{SCOREBOARD_PATH}.tmp"
      File.write(tmp_path, "#{JSON.pretty_generate(rows)}\n")
      File.rename(tmp_path, SCOREBOARD_PATH)
    end

    def load_scoreboard
      return [] unless File.exist?(SCOREBOARD_PATH)

      JSON.parse(File.read(SCOREBOARD_PATH))
    end

    # The reported rate over ALL cases is diagnostic only; the number that
    # matters -- the one item 01's Done-when criteria and AGENTS.md's bar
    # both name -- is over evidence-valid cases (oracle verdict == "valid").
    def rate_over_valid(rows)
      valid = rows.select { |row| row["verdict"] == "valid" }
      [valid.count { |row| row["pass"] }, valid.size]
    end

    def print_summary(rows, label:)
      passed = rows.count { |row| row["pass"] }
      puts format("%s: %d/%d cases render (%.1f%%)", label, passed, rows.size,
                  rows.empty? ? 0.0 : (100.0 * passed / rows.size))

      valid_pass, valid_total = rate_over_valid(rows)
      return if valid_total.zero?

      puts format(
        "  against evidence-valid cases only: %d/%d = %.1f%%",
        valid_pass, valid_total, 100.0 * valid_pass / valid_total
      )
    end

    # `rake corpus` (no type): renders the WHOLE corpus and writes the
    # committed scoreboard. `rake 'corpus[type]'`: a scoped diagnostic view
    # -- prints each failure's case, stage and first error line for that
    # type only, and never touches the committed file. Writing a partial
    # file here would make corpus:check read every OTHER type's absence as
    # every one of its cases regressing.
    def run(type)
      paths = cases(type)
      results = run_cases(paths)
      rows = rows_for_scoreboard(results, verdicts)

      if type
        print_summary(rows, label: "corpus[#{type}]")
        puts
        rows.reject { |row| row["pass"] }.each do |row|
          message = results[row["case"]][:message]
          puts format("  %-55s stage=%-8s %-32s %s", row["case"],
                      row["stage"], row["exception_class"], message)
        end
      else
        write_scoreboard(rows)
        print_summary(rows, label: "corpus")
        puts "wrote #{SCOREBOARD_PATH}"
      end
    end

    # Pure comparison, no I/O -- takes two plain row arrays and says what
    # drifted. Kept separate from check! so it can be unit-tested with
    # synthetic rows instead of the real corpus and the real committed file.
    #
    # A case regresses when the committed row says it passed and the fresh
    # row says it now fails. A case is an unrecorded improvement when the
    # fresh row passes but the committed file does not already say so --
    # that covers both "committed as failing" and "not in the committed
    # file at all" (a case added to the corpus since the last `rake
    # corpus`), because both mean the file needs a fresh `rake corpus` and
    # a commit before it can be trusted again.
    def diff_scoreboards(committed_rows, fresh_rows)
      committed_pass = committed_rows.to_h { |row| [row["case"], row["pass"]] }
      fresh_pass = fresh_rows.to_h { |row| [row["case"], row["pass"]] }

      regressed = fresh_pass.select { |c, pass| committed_pass[c] == true && !pass }
      unrecorded = fresh_pass.select { |c, pass| pass && !committed_pass.fetch(c, false) }

      { regressed: regressed.keys.sort, unrecorded: unrecorded.keys.sort }
    end

    # Fresh run vs. the committed scoreboard. Fails on either drift
    # direction -- the plan's own words are "so the file cannot go stale;
    # you re-run rake corpus and commit the improvement".
    def check!
      committed = load_scoreboard
      if committed.empty?
        abort "scoreboard/corpus.json is missing or empty; run `rake corpus` first."
      end

      fresh_rows = rows_for_scoreboard(run_cases(cases(nil)), verdicts)
      diff = diff_scoreboards(committed, fresh_rows)

      clean = true
      if diff[:regressed].any?
        clean = false
        puts "REGRESSED (passed in the committed scoreboard, fails now):"
        diff[:regressed].each { |c| puts "  #{c}" }
      end
      if diff[:unrecorded].any?
        clean = false
        puts "IMPROVED BUT NOT RECORDED (run `rake corpus` and commit scoreboard/corpus.json):"
        diff[:unrecorded].each { |c| puts "  #{c}" }
      end

      abort "corpus:check: FAILED" unless clean
      puts "corpus:check: clean (#{fresh_rows.size} cases' pass/fail match the committed scoreboard)"
    end
  end
end

desc "Render the spec/mermaid corpus; writes scoreboard/corpus.json. " \
     "Scope to one type with corpus[type] (diagnostic only, does not write)."
task :corpus, [:type] do |_task, args|
  require "sirena"
  Sirena::Corpus.run(args[:type])
end

namespace :corpus do
  desc "Diff a fresh corpus run against the committed scoreboard/corpus.json"
  task :check do
    require "sirena"
    Sirena::Corpus.check!
  end
end
