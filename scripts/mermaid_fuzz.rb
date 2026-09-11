# frozen_string_literal: true

# Shared differential-fuzz harness, factored out of scripts/sequence_fuzz.rb
# so the same driver, comparison logic, and CLI can be reused for every
# diagram type instead of copy-pasted per type.
#
# A per-type script (scripts/flowchart_fuzz.rb, scripts/class_diagram_fuzz.rb,
# scripts/state_diagram_fuzz.rb, scripts/er_diagram_fuzz.rb) supplies only
# what is genuinely type-specific:
#   - a wild-character pool and a source template, fed to the shared
#     IdentifierGenerator below (or a bespoke generator, for a type whose
#     fuzzed surface is not "one bare identifier on its own line" --
#     see IdentifierGenerator's own doc)
#   - a KNOWN_DIVERGENCES regression corpus (see below -- required)
#   - a #sirena_verdict_for(source) that runs THAT type's own parser
#   - the name of a mermaid db getter that returns an id-keyed Map, used
#     for the structural check (getVertices, getClasses, getStates,
#     getEntities, ...) -- pass nil to skip the structural check and
#     compare accept/reject only
#
# This file does not know what a "diagram type" is beyond that contract.
#
# KNOWN_DIVERGENCES is not decoration. dev.md's rule for any detector is
# that a detector never watched go red is a hopeful regex, not a
# detector -- so every per-type script is required to carry at least one
# case, sourced from a real, reproduced disagreement between sirena and
# an actual installed mermaid, that this harness demonstrably flags. A
# type script whose regression corpus is empty prints a loud warning and
# is excluded from the aggregate divergence report until one is added.
#
# That alone is a lower bound: it proves the checker CAN find a bug, but
# not that it won't cry wolf, and not that the GENERATOR producing the
# reported numbers ever explores what it claims to. `Runner#run` (below)
# also runs a negative control (a known-valid source must NOT be flagged)
# and, for a generator that declares one, a check that its wild-character
# pool was actually reached -- see Runner#proven? for why each exists.

require 'json'
require 'open3'
require 'optparse'

module MermaidFuzz
  ROOT = File.expand_path('..', __dir__)
  MERMAID_RUNNER = File.join(ROOT, 'scripts', 'mermaid_fuzz_runner.js')

  # One generated (or fixed) fuzz case: the source text sirena and
  # mermaid both see, and an id used to match up the two sides' results
  # after they are computed independently.
  Case = Struct.new(:id, :source)

  # A generic single-token identifier fuzzer, shared by every diagram
  # type whose fuzzed surface is "one bare identifier, alone on a line,
  # as a whole statement" -- flowchart node ids, class names, state ids,
  # entity ids. Those four differ only in which punctuation is
  # plausible for that token (`wild_chars`) and how the token is
  # embedded in a source string (`template`); the random-walk and
  # length choice are identical, so this class is the one place that
  # logic lives instead of four copies of it.
  #
  # sequence_fuzz.rb's actor-name generator is deliberately NOT
  # rebuilt on top of this: its token sits inside a two-actor arrow
  # statement with its own arrow/message axes, not a single bare line,
  # so the "one token, one template" shape genuinely does not fit it.
  class IdentifierGenerator
    SAFE_CHARS = [*'a'..'z', *'A'..'Z', *'0'..'9', '_'].freeze

    # Shared default wild-character pool for a type with no punctuation
    # of its own to call out (class_diagram, state_diagram, er_diagram
    # all used this exact array, byte-for-byte, before it was named
    # here). flowchart keeps its own narrower pool, which has a stated
    # per-type reason (see flowchart_fuzz.rb); a type whose grammar gives
    # a reason for a wider or narrower set should define its own too,
    # the way class_diagram documents `~` and `<<>>` for generics and
    # stereotypes even though it currently reuses this default.
    DEFAULT_WILD_CHARS = %w[- ( ) % @ / \\ < > + . | ~ $ : *].push(' ').freeze

    # @param rng [Random] seeded RNG, for a reproducible run
    # @param wild_chars [Array<String>] punctuation plausible for this
    #   type's token, mixed 50/50 with SAFE_CHARS
    # @param template [#call(String)] embeds one generated id into a
    #   full diagram source, e.g. ->(id) { "flowchart TD\n    #{id}\n" }
    def initialize(rng, wild_chars:, template:)
      raise ArgumentError, 'wild_chars must not be empty' if wild_chars.empty?

      @rng = rng
      @wild_chars = wild_chars
      @template = template
    end

    def cases(count)
      @last_ids = Array.new(count) { random_id }
      @last_ids.each_with_index.map { |id, i| Case.new("gen-#{i + 1}", @template.call(id)) }
    end

    # Health-check hook Runner calls after generating a batch: true if the
    # random walk visibly reached BOTH pools it claims to draw from at
    # least once. A generator whose wild half never fires -- a mis-wired
    # `wild_chars:` argument, a `pool = ... ? SAFE_CHARS : SAFE_CHARS` typo,
    # a broken RNG branch -- still runs, still returns strings, and the
    # KNOWN_DIVERGENCES corpus alone cannot catch it: those are fixed
    # strings, never actually produced by this generator, so
    # `Runner#run`'s "proven able to go red" check passed on them means
    # nothing about whether the GENERATOR that produces the reported
    # numbers ever explores the space it claims to. Confirmed exactly this
    # gap with a monkeypatched SAFE_CHARS-only generator during review.
    #
    # Checks the RAW GENERATED IDS from the last `cases` call, never the
    # templated source string. The first version of this check scanned
    # `case.source` (the whole `"flowchart TD\n    <id>\n"` string) and was
    # itself broken by the same review: several types' `wild_chars` include
    # a literal space, and every templated source already contains spaces
    # from its own boilerplate (the header, the indent) regardless of what
    # the generator drew, so the check was trivially true no matter how
    # broken `random_char` was. Verified this version actually catches the
    # SAFE_CHARS-only monkeypatch that fooled the source-scanning version.
    def exercised_both_pools?
      ids = @last_ids || []
      ids.any? { |id| id.chars.any? { |c| SAFE_CHARS.include?(c) } } &&
        ids.any? { |id| id.chars.any? { |c| @wild_chars.include?(c) } }
    end

    private

    def random_id
      length = @rng.rand(1..6)
      Array.new(length) { random_char }.join
    end

    def random_char
      pool = @rng.rand < 0.5 ? SAFE_CHARS : @wild_chars
      pool.sample(random: @rng)
    end
  end

  # Drives scripts/mermaid_fuzz_runner.js as a subprocess, once per call,
  # with every case for one diagram type batched together -- batching
  # inside the Node process (one Puppeteer page, many evaluations) is
  # what makes this fast; see the module doc on mermaid_fuzz_runner.js.
  #
  # `getter` names a zero-arg method on the diagram's mermaid db that
  # returns an id-keyed Map/Object/Array (getVertices, getClasses,
  # getStates, getEntities, getActors, ...). Pass nil to skip the
  # structural check and compare accept/reject only.
  #
  # `preflight` is a FIXED, known-valid source for this diagram type
  # (e.g. "flowchart TD\n    A\n"), asserted accepted before any case in
  # `cases` is trusted. It must never be a generated case: a generated
  # case is allowed to be a legitimate rejection, and the runner would
  # then refuse the whole batch mistaking that for a broken Chrome setup.
  module MermaidSide
    module_function

    def run(cases, getter:, preflight:)
      payload = {
        getter: getter,
        preflight: preflight,
        cases: cases.map { |c| { id: c.id, source: c.source } },
      }.to_json
      stdout, stderr, status = Open3.capture3('node', MERMAID_RUNNER, stdin_data: payload)
      raise "mermaid runner failed (exit #{status.exitstatus}):\n#{stderr}" unless status.success?

      JSON.parse(stdout, symbolize_names: true).to_h do |r|
        verdict = r[:accepted] ? { accepted: true, ids: r[:ids] } : { accepted: false, error: r[:error] }
        [r[:id].to_s, verdict]
      end
    end
  end

  # Runs a type-specific verdict proc over every case in-process (no
  # subprocess), reducing each result to the same shape the mermaid side
  # reports: accepted?, and if so, an ordered id list.
  module SirenaSide
    module_function

    def run(cases, verdict_for)
      cases.to_h { |c| [c.id, verdict_for.call(c.source)] }
    end
  end

  # Runs a type's own parser (via the block) and reduces the result to
  # {accepted:, ids:} / {accepted: false, error:}. Every per-type script's
  # SIRENA_VERDICT_FOR wraps its parser call in this rather than
  # hand-rolling `rescue Sirena::Parser::ParseError` four times.
  #
  # Rescues StandardError too, not only ParseError. This is a fuzzer:
  # its entire job is to throw adversarial, previously-untried input at a
  # real parser, and a parser bug that raises something OTHER than its
  # own documented ParseError (a NoMethodError, an ArgumentError, ...) is
  # exactly the kind of thing worth surfacing as a finding -- not a crash
  # that aborts the whole batch and loses every other case's result with
  # it. The "UNEXPECTED" prefix keeps it visibly distinct from a normal,
  # well-formed rejection in any report.
  def self.safe_parse
    { accepted: true, ids: yield }
  rescue Sirena::Parser::ParseError => e
    { accepted: false, error: e.message }
  rescue StandardError => e
    { accepted: false, error: "UNEXPECTED #{e.class}: #{e.message}" }
  end

  # Compares one case's two verdicts and classifies agreement. Identical
  # to sequence_fuzz.rb's Comparison except the structural key is the
  # generic `:ids` rather than sequence's `:actors` -- every type's
  # verdict is normalized to that shape by SirenaSide/MermaidSide above.
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

      id_mismatch
    end

    def accept_reject_mismatch
      [
        :accept_reject_mismatch,
        "sirena accepted=#{@sirena[:accepted]} mermaid accepted=#{@mermaid[:accepted]} " \
          "(sirena: #{@sirena[:error] || @sirena[:ids].inspect}, " \
          "mermaid: #{@mermaid[:error] || @mermaid[:ids].inspect})",
      ]
    end

    def id_mismatch
      if same_ids?
        [:agree, "both accepted, ids=#{@sirena[:ids].inspect}"]
      else
        [:id_mismatch, "sirena ids=#{@sirena[:ids].inspect} mermaid ids=#{@mermaid[:ids].inspect}"]
      end
    end

    # nil on either side means "no structural getter for this type" --
    # treat as agreement, since accept/reject already matched above and
    # that is all this type's script asked to be checked.
    #
    # Order-sensitive by design: every template in this PR produces
    # exactly one id, so order cannot differ. A future generator template
    # that produces MULTIPLE ids per source (a multi-statement diagram,
    # say) would need this reconsidered -- two id lists differing only in
    # order would currently report :id_mismatch, which is correct for one
    # id but would be a false positive for an order-insensitive multi-id
    # comparison.
    def same_ids?
      return true if @sirena[:ids].nil? && @mermaid[:ids].nil?

      @sirena[:ids] == @mermaid[:ids]
    end
  end

  # `Runner#run`'s outcome. `proven` is false when the known-divergence
  # corpus did not reproduce -- see Runner's class doc for why `divergences`
  # and `cases_total` are still meaningful to LOOK at in that case (they are
  # printed either way) but not meaningful to TRUST or aggregate.
  Result = Struct.new(:label, :proven, :cases_total, :divergences, keyword_init: true)

  # Parses CLI options, runs both sides for ONE diagram type, prints the
  # report, and returns a Result (rather than exiting directly) so an
  # aggregate runner can call several types and total them.
  class Runner
    attr_reader :label

    # A known-VALID source (the same one MermaidSide asserts mermaid
    # accepts before trusting anything else) run through BOTH sides and
    # required to come back `:agree`. This is the negative control:
    # without it, a Comparison that always reports a divergence -- or a
    # SIRENA_VERDICT_FOR that always raises -- would still pass the
    # known-divergence check below, because every known divergence IS
    # (trivially) flagged divergent by a checker that flags everything.
    # Confirmed exactly that gap during review: a Comparison monkeypatched
    # to always return divergent still passed the known-divergence-only
    # check.
    AGREEMENT_CASE_ID = 'known-agreement-preflight'

    # @param label [String] diagram type name, for the report header
    # @param generator_factory [#call(rng)] builds a fresh generator (an
    #   object responding to #cases(count)) from a seeded RNG, so a run
    #   is fully reproducible from its seed alone
    # @param known_divergences [Array<Case>] required regression corpus;
    #   see the file banner on why this must be non-empty
    # @param sirena_verdict_for [#call(source)] this type's own parser,
    #   reduced to {accepted:, ids:} / {accepted: false, error:}
    # @param mermaid_getter [String, nil] mermaid db getter name, or nil
    # @param mermaid_preflight [String] a fixed, known-valid source for
    #   this diagram type -- see MermaidSide's doc on why it must be fixed
    def initialize(label:, generator_factory:, known_divergences:, sirena_verdict_for:, mermaid_getter:,
                   mermaid_preflight:)
      @label = label
      @generator_factory = generator_factory
      @known_divergences = known_divergences
      @sirena_verdict_for = sirena_verdict_for
      @mermaid_getter = mermaid_getter
      @mermaid_preflight = mermaid_preflight
    end

    # Builds cases, compares BOTH sides ONCE (a single mermaid_fuzz_runner.js
    # subprocess / single Puppeteer launch for the whole batch -- the
    # agreement case, known divergences, and generated cases together),
    # checks the harness is trustworthy, prints the report, and returns a
    # Result.
    #
    # An earlier version ran `compare` twice per invocation: once inside a
    # separate `proven_to_go_red?` that checked only `known_divergences`,
    # then again here for the full case list, launching Chrome twice for
    # every single-type run and doubling the aggregate report's cost. The
    # agreement case and known divergences are now the head of `cases`, so
    # one comparison pass answers all three questions below.
    def run(seed:, count:, verbose: false)
      generator = @generator_factory.call(Random.new(seed))
      generated = generator.cases(count)
      agreement_case = Case.new(AGREEMENT_CASE_ID, @mermaid_preflight)
      cases = [agreement_case] + @known_divergences + generated
      comparisons = compare(cases)
      agreement_comparison = comparisons.first
      known_comparisons = comparisons[1, @known_divergences.size]
      divergences = comparisons.select(&:divergence?)
      proven = proven?(agreement_comparison, known_comparisons, generator, generated)

      puts "== #{@label} (seed=#{seed}) =="
      warn_unproven(agreement_comparison, known_comparisons, generator, generated) unless proven
      (verbose ? comparisons : divergences).each { |c| puts c }
      puts "#{@label}: #{cases.size} cases, #{divergences.size} divergences " \
           "#{divergences.group_by(&:kind).transform_values(&:size)}"

      Result.new(label: @label, proven: proven, cases_total: cases.size, divergences: divergences)
    end

    private

    # The "proven able to go red" check the PR brief requires before
    # generated numbers are trusted, in three parts:
    #   1. a known-VALID source is NOT flagged (upper bound / negative
    #      control -- catches an always-divergent checker)
    #   2. there IS a known-divergence corpus and EVERY case in it IS
    #      flagged (lower bound / positive control -- the harness can
    #      actually find a real, previously-reproduced bug)
    #   3. IF any cases were generated AND the generator declares a
    #      wild/safe split (duck-typed via #exercised_both_pools?;
    #      sequence_fuzz.rb's own generator does not and is exempt,
    #      matching its exemption from this whole shared library), the
    #      GENERATOR that produced the reported numbers actually reached
    #      both pools at least once. Skipped for a `count: 0` diagnostic
    #      run (only the fixed corpus was asked for, so there is nothing
    #      generated to prove anything about).
    def proven?(agreement_comparison, known_comparisons, generator, generated)
      return false if agreement_comparison.divergence?
      return false if @known_divergences.empty?
      return false unless known_comparisons.all?(&:divergence?)
      return false if generated.any? && generator.respond_to?(:exercised_both_pools?) && !generator.exercised_both_pools?

      true
    end

    def warn_unproven(agreement_comparison, known_comparisons, generator, generated)
      if agreement_comparison.divergence?
        warn "#{@label}: NEGATIVE CONTROL FAILED -- a known-valid source was flagged as a " \
             "divergence: #{agreement_comparison}. The checker itself is untrustworthy."
      end

      if @known_divergences.empty?
        warn "#{@label}: NO known-divergence regression case -- " \
             'this generator has never been shown to catch anything real. ' \
             'See mermaid_fuzz.rb banner.'
      elsif !known_comparisons.all?(&:divergence?)
        caught = known_comparisons.count(&:divergence?)
        warn "#{@label}: #{caught}/#{@known_divergences.size} known divergences caught -- " \
             'a regression case stopped diverging. Investigate before trusting this run.'
        known_comparisons.reject(&:divergence?).each { |c| warn "  NOT caught: #{c}" }
      end

      if generated.any? && generator.respond_to?(:exercised_both_pools?) && !generator.exercised_both_pools?
        warn "#{@label}: GENERATOR NEVER EXPLORED ITS WILD CHARACTER POOL across " \
             "#{generated.size} generated cases -- the reported numbers test nothing beyond " \
             'safe identifiers. Check the generator_factory wiring.'
      end
    end

    def compare(cases)
      sirena_results = SirenaSide.run(cases, @sirena_verdict_for)
      mermaid_results = MermaidSide.run(cases, getter: @mermaid_getter, preflight: @mermaid_preflight)
      cases.map { |c| Comparison.new(c, sirena_results[c.id], mermaid_results[c.id]) }
    end
  end

  # Standalone CLI for a single type's fuzz script. Close to
  # sequence_fuzz.rb's own CLI (same --seed/--count/--verbose options, same
  # exit-code shape) but not identical: it drops sequence_fuzz.rb's timing
  # output, and it adds the exit(2) "not proven" gate below, which
  # sequence_fuzz.rb does not have (its known divergences are merged into
  # `cases` unconditionally, with no separate pass/fail check).
  class CLI
    def self.run(argv, **runner_kwargs)
      new(argv, **runner_kwargs).run
    end

    def initialize(argv, **runner_kwargs)
      @seed = nil
      @count = 500
      @verbose = false
      parse!(argv)
      @runner = Runner.new(**runner_kwargs)
    end

    def run
      seed = @seed || Random.new_seed
      result = @runner.run(seed: seed, count: @count, verbose: @verbose)
      exit(2) unless result.proven
      exit(result.divergences.empty? ? 0 : 1)
    end

    private

    def parse!(argv)
      OptionParser.new do |o|
        o.on('--seed N', Integer) { |v| @seed = v }
        o.on('--count N', Integer) { |v| @count = v }
        o.on('--verbose') { @verbose = true }
      end.parse!(argv)
    end
  end
end
