# frozen_string_literal: true

# Differential fuzz harness for Sirena's sequence-diagram grammar.
#
# Generates random single-message sequence-diagram sources, parses each
# with Sirena's own Parslet grammar, and asks a real, installed mermaid
# (via scripts/sequence_fuzz_mermaid.js, driven inside one persistent
# headless-Chrome page) whether it agrees. It reports two kinds of
# disagreement: one side accepts and the other rejects, or both accept
# but disagree on the actor names.
#
# Tooling only. Does not ship in the gem, is not required by lib/sirena,
# and is not exercised by `rake`/`rspec`.
#
# Usage:
#   ruby scripts/sequence_fuzz.rb [--seed N] [--count N] [--verbose]
#
#   --seed N     replay a specific run. Always printed, so any run can be
#                reproduced exactly: `ruby scripts/sequence_fuzz.rb --seed 12345`
#   --count N    how many RANDOM cases to generate, on top of the fixed
#                regression corpus below (default 500)
#   --verbose    print every case, not just the divergences
#
# Exit status: 0 if sirena and mermaid agreed on every case (regression
# corpus included), 1 if any divergence was found. That makes it usable
# as a gate; see the timing section printed at the end for whether that
# is actually fast enough to run on every grammar change.
#
# WHAT THIS GENERATES, AND WHAT IT DOES NOT
#
# Every case has the fixed shape:
#
#   sequenceDiagram
#       <actor-a><arrow><actor-b>[: <message>]
#
# one statement, one line. The random axis is the ACTOR NAME token,
# because that is what PR #38 spent five review rounds on (widening
# `identifier` from `[a-zA-Z_][a-zA-Z0-9_]*` to what mermaid's own
# lexer accepts there). The arrow is always one of mermaid's real arrow
# spellings; message text, when present, is plain ASCII.
#
# Token classes generated for an actor name:
#   - "safe" identifier characters: letters, digits, underscore
#   - "wild" characters drawn from the exact set PR #38's fix commits
#     measured as significant for mermaid's actor lexer: - ( ) % @ / \
#     < > + . space |
#   - names 1-6 characters long, mixing both pools
#
# Token classes this harness does NOT generate, and does not claim to
# cover:
#   - participant/actor DECLARATIONS (`participant A as B`) -- only bare
#     message endpoints. The real grammar treats declared and
#     message-endpoint names as different token classes (see
#     `declaration_name` vs `message_actor_name` in the #38 branch); this
#     harness only fuzzes the message-endpoint class.
#   - notes, activation/deactivation keywords, loop/alt/opt/par/critical/
#     break blocks, box grouping, `as` aliasing, `@{...}` shape metadata,
#     quoted strings, multi-statement diagrams, non-ASCII text
#   - malformed or partial arrows -- arrows are always one of a fixed,
#     valid list, never fuzzed themselves
#   - message text beyond a small fixed pool of plain-ASCII strings
#
# A clean run says nothing about any of the above; it only says these two
# parsers agree on how to identify an actor's name in a single message
# statement.

require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require 'json'
require 'open3'
require 'optparse'

module SequenceFuzz
  ROOT = File.expand_path('..', __dir__)
  MERMAID_RUNNER = File.join(ROOT, 'scripts', 'sequence_fuzz_mermaid.js')

  # Exact arrow spellings mermaid's own sequence lexer draws (mirrors the
  # list in lib/sirena/parser/grammars/sequence.rb). The arrow token is
  # deliberately NOT fuzzed -- only real spellings are used, so every
  # divergence found is attributable to the actor-name token.
  ARROWS = %w[
    ->> --> -> --) -) --x -x --// -// --\\ -\\ --|/ -|/ --|\\ -|\\
  ].freeze

  SAFE_ACTOR_CHARS = [*'a'..'z', *'A'..'Z', *'0'..'9', '_'].freeze

  # Characters PR #38's fix measured as significant for mermaid's actor
  # lexer (dash-fusion, central-connection parens, comment/shape-metadata
  # openers, reversed-arrow leads). Kept narrow and named rather than
  # "everything printable" -- an unbounded alphabet would make a
  # divergence's cause harder to read off the failing input, not easier.
  WILD_ACTOR_CHARS = %w[- ( ) % @ / \\ < > + . |].push(' ').freeze

  MESSAGE_TEXTS = ['', 'hello', 'a message with spaces', 'msg 123'].freeze

  # One generated (or fixed) fuzz case: the source text sirena and
  # mermaid both see, and an id used to match up the two sides' results
  # after they are computed independently.
  Case = Struct.new(:id, :source)

  # The two known divergences PR #38's round 4 found against real
  # mermaid, run on main (85acf20) before #38's actor-name widening
  # lands. Always included, regardless of seed, so a run of this harness
  # can always prove it still catches at least one of them -- the
  # "known-positive" this whole harness is required to go red on.
  #
  # Measured this session against main (85acf20): the FIRST case still
  # diverges exactly as an ACCEPT/REJECT mismatch (sirena rejects,
  # mermaid accepts "B", "A-(%%C"). The SECOND case does not currently
  # diverge on main -- sirena's narrow `identifier` already rejects it
  # for an unrelated reason, and so does mermaid, so both sides agree
  # (REJECT/REJECT) until #38 widens the actor-name token. It stays in
  # the regression corpus because #38 landing is exactly the change that
  # could make it start disagreeing.
  KNOWN_DIVERGENCES = [
    Case.new('known-1-dash-paren-comment', "sequenceDiagram\n    B->>A-(%%C: m\n"),
    Case.new('known-2-reversed-arrow-lead', "sequenceDiagram\n    A-(//-B: m\n"),
  ].freeze

  # Generates random single-message sequence-diagram sources with a
  # deterministic RNG, so a run is fully reproducible from its seed.
  class Generator
    def initialize(rng)
      @rng = rng
    end

    def cases(count)
      (1..count).map { |i| Case.new("gen-#{i}", generate_source) }
    end

    private

    def generate_source(*)
      "sequenceDiagram\n    #{random_actor}#{random_arrow}#{random_actor}#{random_message}\n"
    end

    def random_arrow
      ARROWS.sample(random: @rng)
    end

    def random_actor
      length = @rng.rand(1..6)
      Array.new(length) { random_actor_char }.join
    end

    def random_actor_char
      pool = @rng.rand < 0.5 ? SAFE_ACTOR_CHARS : WILD_ACTOR_CHARS
      pool.sample(random: @rng)
    end

    def random_message
      text = MESSAGE_TEXTS.sample(random: @rng)
      text.empty? ? '' : ": #{text}"
    end
  end

  # Runs Sirena's own SequenceParser in-process (no subprocess) and
  # reduces the result to the same shape the mermaid side reports:
  # accepted?, and if so, the actor id list in first-appearance order.
  module SirenaSide
    module_function

    def run(cases)
      cases.to_h { |c| [c.id, verdict_for(c.source)] }
    end

    def verdict_for(source)
      diagram = Sirena::Parser::SequenceParser.new.parse(source)
      { accepted: true, actors: diagram.participants.map(&:id) }
    rescue Sirena::Parser::ParseError => e
      { accepted: false, error: e.message }
    end
  end

  # Drives scripts/sequence_fuzz_mermaid.js as a subprocess, once, with
  # every case batched into a single call -- batching inside the Node
  # process (one Puppeteer page, many evaluations) is what makes this
  # fast; see the module doc on sequence_fuzz_mermaid.js.
  module MermaidSide
    module_function

    def run(cases)
      payload = cases.map { |c| { id: c.id, source: c.source } }.to_json
      stdout, stderr, status = Open3.capture3('node', MERMAID_RUNNER, stdin_data: payload)
      raise "mermaid runner failed (exit #{status.exitstatus}):\n#{stderr}" unless status.success?

      JSON.parse(stdout, symbolize_names: true).to_h do |r|
        verdict = r[:accepted] ? { accepted: true, actors: r[:actors] } : { accepted: false, error: r[:error] }
        [r[:id].to_s, verdict]
      end
    end
  end

  # Compares one case's two verdicts and classifies agreement.
  class Comparison
    attr_reader :kind, :detail

    def initialize(kase, sirena, mermaid)
      @kase = kase
      @sirena = sirena
      @mermaid = mermaid
      @kind, @detail = classify
    end

    def divergence?
      kind != :agree
    end

    def to_s
      "[#{kind}] #{@kase.id}: #{@kase.source.inspect} -- #{detail}"
    end

    private

    def classify
      return accept_reject_mismatch unless @sirena[:accepted] == @mermaid[:accepted]
      return [:agree, 'both rejected'] unless @sirena[:accepted]

      actor_mismatch
    end

    def accept_reject_mismatch
      [
        :accept_reject_mismatch,
        "sirena accepted=#{@sirena[:accepted]} mermaid accepted=#{@mermaid[:accepted]} " \
          "(sirena: #{@sirena[:error] || @sirena[:actors].inspect}, " \
          "mermaid: #{@mermaid[:error] || @mermaid[:actors].inspect})",
      ]
    end

    def actor_mismatch
      if @sirena[:actors] == @mermaid[:actors]
        [:agree, "both accepted, actors=#{@sirena[:actors].inspect}"]
      else
        [:actor_mismatch, "sirena actors=#{@sirena[:actors].inspect} mermaid actors=#{@mermaid[:actors].inspect}"]
      end
    end
  end

  # Parses CLI options, runs both sides, prints the report, and sets the
  # process exit status.
  class CLI
    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @seed = nil
      @count = 500
      @verbose = false
      parse!(argv)
    end

    def run
      seed = @seed || Random.new_seed
      puts "seed=#{seed}"
      rng = Random.new(seed)

      cases = KNOWN_DIVERGENCES + Generator.new(rng).cases(@count)
      report(cases, *time_both_sides(cases))
    end

    private

    def parse!(argv)
      OptionParser.new do |o|
        o.on('--seed N', Integer) { |v| @seed = v }
        o.on('--count N', Integer) { |v| @count = v }
        o.on('--verbose') { @verbose = true }
      end.parse!(argv)
    end

    def time_both_sides(cases)
      start = Time.now
      sirena_results = SirenaSide.run(cases)
      sirena_elapsed = Time.now - start

      start = Time.now
      mermaid_results = MermaidSide.run(cases)
      mermaid_elapsed = Time.now - start

      [sirena_results, mermaid_results, sirena_elapsed, mermaid_elapsed]
    end

    def report(cases, sirena_results, mermaid_results, sirena_elapsed, mermaid_elapsed)
      comparisons = cases.map { |c| Comparison.new(c, sirena_results[c.id], mermaid_results[c.id]) }
      divergences = comparisons.select(&:divergence?)

      print_cases(comparisons, divergences)
      print_timings(cases.size, sirena_elapsed, mermaid_elapsed)
      print_summary(cases.size, divergences)

      exit(divergences.empty? ? 0 : 1)
    end

    def print_cases(comparisons, divergences)
      (@verbose ? comparisons : divergences).each { |c| puts c }
    end

    def print_timings(total, sirena_elapsed, mermaid_elapsed)
      puts format('sirena:  %d cases in %.3fs (%.1f/s)', total, sirena_elapsed, total / sirena_elapsed)
      puts format('mermaid: %d cases in %.3fs (%.1f/s)', total, mermaid_elapsed, total / mermaid_elapsed)
    end

    def print_summary(total, divergences)
      by_kind = divergences.group_by(&:kind).transform_values(&:size)
      puts "#{total} cases, #{divergences.size} divergences #{by_kind}"
    end
  end
end

SequenceFuzz::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
