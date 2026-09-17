# frozen_string_literal: true

# Runs every registered per-type differential fuzz harness under scripts/
# and prints one aggregate table: cases, divergences, and a kind
# breakdown, per diagram type. This is the "report divergence counts per
# type" deliverable -- the individual *_fuzz.rb scripts remain runnable
# and useful on their own (for --verbose drill-down on one type), but
# this is the single command that answers "how does each type compare".
#
# scripts/sequence_fuzz.rb is intentionally NOT included here. It
# predates this file, has its own established CLI and report format,
# and stays that way; duplicating its reporting here would mean parsing
# a sibling script's stdout for no real benefit. Run it separately:
#   ruby scripts/sequence_fuzz.rb --seed N --count N
#
# Tooling only. Does not ship in the gem, is not required by lib/sirena,
# and is not exercised by `rake`/`rspec`.
#
# Usage:
#   ruby scripts/diagram_fuzz_report.rb [--seed N] [--count N]
#
#   --seed N   same seed used for every type. Types have independent
#              generators (different token pools, different templates),
#              so a shared seed does not mean shared cases; it only
#              makes the whole report reproducible from one number.
#   --count N  random cases PER TYPE, on top of that type's own fixed
#              known-divergence corpus (default 500)
#
# Every type's harness is proven trustworthy (see mermaid_fuzz.rb's
# Runner#run) before its numbers are printed -- a type whose checker or
# generator silently broke does not get to report a plausible-looking
# number next to the others' real output.
#
# Exit status: 2 if ANY type is unproven (a broken detector, not a
# measurement -- checked and reported FIRST, regardless of what the
# other types found, so this can never be confused with exit 1 below).
# Otherwise: 0 if every type agreed on every case, 1 if any type had at
# least one real divergence.

require 'bundler/setup'
require 'optparse'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require_relative 'mermaid_fuzz'
require_relative 'flowchart_fuzz'
require_relative 'class_diagram_fuzz'
require_relative 'state_diagram_fuzz'
require_relative 'er_diagram_fuzz'

module DiagramFuzzReport
  # Order matches the mermaid-js corpus case count per type, highest
  # first, per the task brief ("start with the types that have the most
  # cases under spec/mermaid/"). Measured this session, both figures from
  # this exact command (only the directory name changes):
  #
  #   find spec/mermaid/<dir> -name '*.mmd' | wc -l
  #
  # combining the two extraction batches that share one registered
  # diagram type (spec/mermaid/class + spec/mermaid/class_diagram are
  # both `:class_diagram`, and likewise state/state_diagram,
  # er/er_diagram, git/gitgraph -- see lib/sirena.rb's DiagramRegistry.register calls):
  #
  #   class_diagram   465  (class 181 + class_diagram 284)
  #   flowchart       331
  #   state_diagram   234  (state 61 + state_diagram 173)
  #   git_graph       168  (git 161 + gitgraph 7)
  #   er_diagram      161  (er 61 + er_diagram 100)
  #
  # git_graph actually has MORE cases than er_diagram, not a tie -- not
  # covered by this PR regardless; see the note at the bottom of this file.
  TARGETS = [
    ClassDiagramFuzz::RUNNER_KWARGS,
    FlowchartFuzz::RUNNER_KWARGS,
    StateDiagramFuzz::RUNNER_KWARGS,
    ErDiagramFuzz::RUNNER_KWARGS,
  ].freeze

  class CLI
    def self.run(argv) = new(argv).run

    def initialize(argv)
      @seed = nil
      @count = 500
      parse!(argv)
    end

    def run
      seed = @seed || Random.new_seed
      puts "seed=#{seed} (shared across types; see file banner)"

      # Each Runner#run is ONE mermaid_fuzz_runner.js launch that both
      # proves its own harness and produces the real numbers -- see
      # mermaid_fuzz.rb's Runner#run doc for why this is a single pass
      # rather than a separate proof step per type. That is one browser
      # launch PER TYPE (4 total here), not one for the whole report --
      # merging all 4 types into a single Puppeteer page would need
      # mermaid_fuzz_runner.js's payload to carry a getter/preflight per
      # CASE rather than per batch, which is a real redesign, not
      # something to fold into this PR.
      results = TARGETS.map { |kwargs| MermaidFuzz::Runner.new(**kwargs).run(seed: seed, count: @count) }

      unproven, proven = results.partition { |r| !r.proven }
      unproven.each { |r| warn "#{r.label}: EXCLUDED from the table below -- its own harness is not proven trustworthy." }

      print_table(proven)

      # Unproven is checked and reported FIRST and unconditionally: a
      # broken detector must never be masked by, or confused with, a
      # real divergence found elsewhere. An earlier version returned the
      # same exit code (1) for both, which a caller reading only the
      # exit status could not tell apart -- confirmed independently by
      # three reviewers during this PR's own review.
      exit(2) unless unproven.empty?

      any_divergences = proven.any? { |r| !r.divergences.empty? }
      exit(any_divergences ? 1 : 0)
    end

    private

    def parse!(argv)
      OptionParser.new do |o|
        o.on('--seed N', Integer) { |v| @seed = v }
        o.on('--count N', Integer) { |v| @count = v }
      end.parse!(argv)
    end

    def print_table(results)
      puts "\n== summary =="
      puts 'type               cases  divergences   breakdown'
      results.each do |r|
        by_kind = r.divergences.group_by(&:kind).transform_values(&:size)
        puts format('%-15s %8d %12d   %s', r.label, r.cases_total, r.divergences.size, by_kind)
      end
    end
  end
end

DiagramFuzzReport::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__

# Why git_graph stops here rather than being the fifth type, EVEN THOUGH
# its corpus (168) is larger than er_diagram's (161): its structural
# check is genuinely different in shape (commit/branch refs and a DAG,
# not a single id-keyed statement), so it needs its own generator design
# rather than a copy of the "one bare identifier line" template every
# type above shares. Er_diagram's grammar (entity_declaration is a bare
# `identifier` line, exactly like the four types above) let it reuse the
# same generator shape and reach a proven, real known-divergence case
# inside this PR's scope. Extending this file with a fifth,
# git_graph-specific generator is follow-on work.
