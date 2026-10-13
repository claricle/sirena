# frozen_string_literal: true

require "spec_helper"
require "svg_conform"
require "date"
require "rexml/document"
require "timeout"
require "yaml"

# The gate: output must stay svg_conform-conformant, not just "renders
# something". Three populations checked differently because they fail
# differently -- examples/ SVGs as on-disk FILES globbed off disk (intended
# to feed the docs site once TODO.foundation/15 wires that build up; no
# workflow ships them to a reader today), reference fixtures as the per-type
# shape, and the 1,997-source mermaid corpus as the wide net (floor-guarded,
# not counted -- see CONFORMANCE_RENDERABLE_FILE below).
CONFORMANCE_ROOT = SpecSupport::RepositoryPaths::ROOT

# Globbed directly, not asked of the gemspec: since D6 (sirena.gemspec's
# `files` became a lib+exe allowlist), examples/ no longer ships inside the
# gem, but the on-disk SVGs are still meant to feed the docs site build
# (per TODO.foundation/15, not yet wired) and still need a conformance guard.
CONFORMANCE_EXAMPLE_SVGS =
  (Dir.glob(File.join(CONFORMANCE_ROOT, "examples", "*.svg")) +
   Dir.glob(File.join(CONFORMANCE_ROOT, "examples", "*", "*.svg"))).freeze
CONFORMANCE_FIXTURE_SOURCES = Dir.glob(
  File.join(CONFORMANCE_ROOT, "spec", "fixtures", "*", "input.mmd"),
).freeze
CONFORMANCE_CORPUS_SOURCES = Dir.glob(
  File.join(CONFORMANCE_ROOT, "spec", "mermaid", "*", "*.mmd"),
).freeze
CONFORMANCE_EXAMPLE_SOURCES = Dir.glob(
  File.join(CONFORMANCE_ROOT, "examples", "*", "*.mmd"),
).freeze

# Which corpus cases render today, by NAME not count -- a count can't see
# a regressing case swap places with a gaining one. A floor, not an
# equality: additions are free (item 06 raises this weekly), only a case
# that STOPS rendering fails it.
#
# Regenerate after a real gain with
# `CONFORMANCE_WRITE_RENDERABLE=1 bundle exec rspec
# spec/svg_conformance_spec.rb`.
CONFORMANCE_RENDERABLE_FILE = File.join(
  CONFORMANCE_ROOT, "spec", "mermaid", "corpus-renderable.txt"
)

# The size the baseline itself must not fall below. It guards the guard: an
# emptied or truncated list would make the subset check pass against nothing.
# Same population `scripts/corpus_sweep.rb` counts by the same criterion.
#
# Dropped from 898 to 877 for two groups of oracle-backed correctness fixes.
#
# kanban/knbn_6_real_root_in_wrong_place-7a57fb5a ("real root in wrong
# place") used to "render" by dropping its first two items. Real mermaid
# rejects it ("Items without section detected"), so Sirena raising
# ParseError now is a correctness win.
#
# mindmap/5_multiple_roots_are_illegal-4fbe4e9a ("multiple roots are
# illegal") and mindmap/mmp_6_real_root_in_wrong_place-226e3b49 ("real
# root in wrong place") used to "render" by silently dropping the true
# root and its whole subtree when a second level-zero node appeared. Real
# mermaid rejects both (`mermaid.parse` on 11.12.0 raises "There can be only
# one root."), so Sirena now correctly raising ParseError for them is a
# correctness win, not a coverage loss.
#
# mindmap/mindmap_spec-de34c92b is different: it is `root(\n  The root\n)`,
# a single node using round-shape syntax with its text on its own line. Real
# mermaid parses that as ONE node (verified via mermaid's own db on 11.12.0: one
# node, id "root", descr "The root", no children) -- Sirena should render
# it, not reject it. The grammar has no round-shape `(text)` rule and treats
# each physical line as its own node, so it produces three fake level-0
# siblings and the multiple-roots guard above (correct for 031/032) fires
# on this case too. That guard did not regress; the gap is round-shape and
# multi-line node text, which Sirena never supported before this diff
# either (main silently mis-split it into a 2-node tree that happened to
# still look SVG-shaped). Backlogged, not fixed here -- fixing it means
# multi-line node grammar support, out of scope for this bucket.
#
# Seventeen more cases used to render only because C4 and Class accepted
# malformed declarations and GitGraph accepted operations Mermaid rejects.
# Every case is pinned `invalid` in scoreboard/corpus.json. Rejecting them is
# therefore a compatibility gain, not a loss of oracle-valid coverage.
CONFORMANCE_RENDERED_FLOOR = 1206

# The example sources Sirena cannot parse yet, so they have no checked-in
# SVG. Named rather than counted: a NEW source falling out of the checked-in
# set is a regression, and a glob over whatever happens to exist cannot see
# one.
CONFORMANCE_UNRENDERABLE_EXAMPLES = [].freeze

# Same guard corpus_sweep.rb uses. A case that hangs is a corpus problem, not
# a conformance one, and it must not hang the suite.
CONFORMANCE_CASE_TIMEOUT = 10
CONFORMANCE_EXAMPLE_TODAY = Date.new(2026, 1, 1)
CONFORMANCE_EXAMPLE_THEME = "default"

module SvgConformanceSpecHelpers
  def validate(svg)
    SvgConform.validate(svg, profile: Sirena::Svg::CONFORMANCE_PROFILE)
  end

  # Needed alongside svg_conform, not redundant with it: svg_conform never
  # parses, so it answers `valid?` true for an unclosed tag, a mismatched
  # pair, a raw `&`, a missing `</svg>` -- don't drop this assuming
  # conformance alone catches malformed XML.
  #
  # @return [String, nil] the parse error, or nil when the document parses
  def corpus_conformance_observation
    baseline = baseline_renderable
    checks = [baseline.size, baseline.uniq]
    observation = { baseline: baseline, checks: checks }
    return observation unless checks[0] >= CONFORMANCE_RENDERED_FLOOR &&
      checks[1] == baseline

    rendered, offenders = collect_corpus_conformance
    checks.push(baseline - rendered, offenders)
    observation.merge(rendered: rendered)
  end

  def collect_corpus_conformance
    rendered = []
    offenders = CONFORMANCE_CORPUS_SOURCES.filter_map do |source_path|
      corpus_conformance_problem(source_path, rendered)
    end
    [rendered, offenders]
  end

  def corpus_conformance_problem(source_path, rendered)
    svg = render_or_skip(source_path)
    return unless svg

    rendered << corpus_name(source_path)
    malformed = parse_error(svg)
    if malformed
      path = source_path.sub("#{CONFORMANCE_ROOT}/", "")
      return "#{path}: not well-formed: #{malformed}"
    end
    result = validate(svg)
    complaint(source_path, result) unless result.valid?
  end

  def corpus_conformance_message(observation)
    lost, offenders = observation.fetch(:checks).drop(2)
    return "damaged conformance baseline" unless lost && offenders

    "stopped rendering, so nothing checked them: #{lost.sort.join(', ')}\n" \
      "#{offenders.join("\n")}"
  end

  def write_corpus_improvement(observation)
    return unless ENV["CONFORMANCE_WRITE_RENDERABLE"]

    write_renderable(observation.fetch(:rendered))
  end

  def stale_example_message(comparison)
    "not tracked, or not what the renderer produces: " \
      "#{comparison.fetch(:stale).join(', ')}"
  end

  def parse_error(svg)
    REXML::Document.new(svg)
    nil
  rescue REXML::ParseException => e
    e.message.lines.first.to_s.strip
  end

  def complaint(path, result)
    messages = (result.errors + result.validity_errors).map(&:message).uniq
    summary = messages.first(3).join(" | ")
    remaining = messages.size - 3
    summary += " | #{remaining} more" if remaining.positive?

    "#{path.sub("#{CONFORMANCE_ROOT}/", '')}: #{summary}"
  end

  # Output that claims to be an SVG document. One rule, used by both
  # populations that ask the question: a substring test here and an anchored
  # one below were two spellings of it, and the looser one would have counted
  # a document with anything in front of the root.
  #
  # @return [Boolean] whether the value is a document to judge
  def svg_document?(value)
    value.is_a?(String) && value.match?(/\A<svg(?:\s|>)/)
  end

  # A corpus case as the baseline names it: `<type>/<case>.mmd`, the same key
  # `scripts/corpus_sweep.rb --failing` prints, so the two lists compare.
  def corpus_name(path)
    path.sub("#{File.join(CONFORMANCE_ROOT, 'spec', 'mermaid')}/", "")
  end

  # Read fresh, not memoized: the one caller regenerates the file it just
  # read, and a remembered list would answer for the version before that.
  def baseline_renderable
    File.readlines(CONFORMANCE_RENDERABLE_FILE, chomp: true).reject(&:empty?)
  end

  # Writes the baseline from the run that just measured it, so the list and
  # the gate can never be two spellings of "renders to a document".
  def write_renderable(names)
    File.write(CONFORMANCE_RENDERABLE_FILE, "#{names.sort.join("\n")}\n")
  end

  # A case Sirena cannot render is item 06's problem, not this gate's.
  #
  # The date is pinned for the same reason it is pinned for the examples:
  # eight gantt cases place bars relative to today, so an unpinned run judges
  # different documents every day.
  def render_or_skip(path)
    svg = Timeout.timeout(CONFORMANCE_CASE_TIMEOUT) do
      Sirena::Engine.new.render(
        File.read(path), today: CONFORMANCE_EXAMPLE_TODAY
      )
    end
    svg if svg_document?(svg)
  rescue StandardError
    nil
  end
end

# Helpers for the nested 'the checked-in examples' describe block below.
module SvgConformanceCheckedInExampleHelpers
  def example_task_source
    path = File.join(CONFORMANCE_ROOT, "tasks", "example_tasks.rb")
    File.read(path)
  end

  def unrenderable_example_source_lines
    CONFORMANCE_UNRENDERABLE_EXAMPLES
      .map { |source| "  \"#{source}\"," }.join("\n")
  end

  # The same inputs examples.rake uses. The date is pinned there because
  # gantt and timeline place bars relative to today, so an unpinned render
  # differs from identical source every day.
  def render_example(mmd_path)
    metadata_path = mmd_path.sub(/\.mmd\z/, ".yml")
    metadata = File.exist?(metadata_path) ? YAML.load_file(metadata_path) : {}
    # Same cap as render_or_skip, and for the same reason: a pathological
    # source must fail this example, not hang the whole suite.
    Timeout.timeout(CONFORMANCE_CASE_TIMEOUT) do
      # This mirrors examples.rake's theme/today arguments, unlike the
      # corpus's Engine call.
      Sirena.render(
        File.read(mmd_path),
        theme: metadata["theme"] || CONFORMANCE_EXAMPLE_THEME,
        today: CONFORMANCE_EXAMPLE_TODAY,
      )
    end
  end

  def relative(path)
    path.sub("#{CONFORMANCE_ROOT}/examples/", "")
  end

  # Every source that is not named unrenderable owes exactly one SVG.
  def expected_svgs
    (CONFORMANCE_EXAMPLE_SOURCES.map { |mmd| relative(mmd) } -
      CONFORMANCE_UNRENDERABLE_EXAMPLES)
      .map { |mmd| mmd.sub(/\.mmd\z/, ".svg") }
  end
end

RSpec.describe Sirena::Svg do
  def expected_unrenderable_declaration(sources)
    return "EXPECTED_UNRENDERABLE_SOURCES = [].freeze" if sources.empty?

    "EXPECTED_UNRENDERABLE_SOURCES = [\n#{sources}\n].freeze"
  end

  include SvgConformanceSpecHelpers

  describe "conformance of the checked-in example SVGs" do
    it "has some" do
      expect(CONFORMANCE_EXAMPLE_SVGS).not_to be_empty
    end

    CONFORMANCE_EXAMPLE_SVGS.each do |svg_path|
      describe "#{svg_path.sub("#{CONFORMANCE_ROOT}/", '')} conformance" do
        subject(:content) { File.read(svg_path) }

        let(:malformed) { parse_error(content) }
        let(:malformed_message) do
          -> { "#{svg_path.sub("#{CONFORMANCE_ROOT}/", '')}: #{malformed}" }
        end
        let(:result) { validate(content) }

        it "contains nonempty SVG bytes" do
          expect(content).not_to be_empty
        end

        it "contains well-formed XML" do
          expect(malformed).to be_nil, malformed_message
        end

        it "satisfies the chosen SVG conformance profile" do
          expect(result).to be_valid, -> { complaint(svg_path, result) }
        end
      end
    end
  end

  describe "conformance of the reference fixtures" do
    it "has reference fixtures to render" do
      expect(CONFORMANCE_FIXTURE_SOURCES).not_to be_empty
    end

    CONFORMANCE_FIXTURE_SOURCES.each do |source_path|
      describe "#{File.basename(File.dirname(source_path))} conformance" do
        subject(:svg) { Sirena::Engine.new.render(File.read(source_path)) }

        let(:malformed) { parse_error(svg) }
        let(:malformed_message) do
          -> { "#{source_path.sub("#{CONFORMANCE_ROOT}/", '')}: #{malformed}" }
        end
        let(:result) { validate(svg) }

        it "renders well-formed XML" do
          expect(malformed).to be_nil, malformed_message
        end

        it "renders conformant SVG" do
          expect(result).to be_valid, -> { complaint(source_path, result) }
        end
      end
    end
  end

  describe "conformance across the mermaid corpus" do
    # Read and check baseline integrity before any renderer runs. All four
    # facts must hold before the optional write can record an improvement.
    let(:corpus_observation) { corpus_conformance_observation }
    let(:checks) { corpus_observation.fetch(:checks) }
    let(:corpus_message) do
      -> { corpus_conformance_message(corpus_observation) }
    end
    let(:corpus_contract) do
      [be >= CONFORMANCE_RENDERED_FLOOR,
       corpus_observation.fetch(:baseline), [], []]
    end

    it "renders every case it can render conformantly" do
      expect(checks).to match(corpus_contract), corpus_message
      write_corpus_improvement(corpus_observation)
    end

    describe "baseline guards" do
      before do
        allow(self).to receive(:collect_corpus_conformance)
          .and_raise("rendering began before baseline validation")
      end

      it "rejects a truncated baseline before rendering" do
        allow(self).to receive(:baseline_renderable).and_return([])
        expect(corpus_observation.fetch(:checks)).not_to match(corpus_contract)
      end

      it "rejects duplicate entries before rendering" do
        duplicate = Array.new(CONFORMANCE_RENDERED_FLOOR, "same-case")
        allow(self).to receive(:baseline_renderable).and_return(duplicate)
        expect(corpus_observation.fetch(:checks)).not_to match(corpus_contract)
      end

      it "rejects a lost case even when the offender list is empty" do
        baseline = baseline_renderable
        allow(self).to receive(:collect_corpus_conformance)
          .and_return([baseline.drop(1), []])
        expect(corpus_observation.fetch(:checks)).not_to match(corpus_contract)
      end
    end
  end

  # The gate above judges the SVGs that happen to be on disk, which is not
  # the same question. Presence proves nothing about whether the renderer
  # still works, or whether what is checked in is what the renderer produces
  # today. Both are rendered here rather than looked for.
  describe "the checked-in examples" do
    include SvgConformanceCheckedInExampleHelpers

    let(:example_comparison) do
      compared = 0
      stale = CONFORMANCE_EXAMPLE_SOURCES.filter_map do |mmd|
        rendered = begin
          render_example(mmd)
        rescue StandardError
          next
        end
        compared += 1
        svg_path = mmd.sub(/\.mmd\z/, ".svg")
        unless CONFORMANCE_EXAMPLE_SVGS.include?(svg_path)
          next relative(svg_path)
        end

        relative(svg_path) unless File.read(svg_path) == rendered
      end
      expected_count = CONFORMANCE_EXAMPLE_SOURCES.size -
        CONFORMANCE_UNRENDERABLE_EXAMPLES.size
      { compared: compared, stale: stale, expected_count: expected_count }
    end
    let(:example_rendering) do
      rendered = {}
      unrenderable = CONFORMANCE_EXAMPLE_SOURCES.filter_map do |mmd|
        rendered[mmd] = render_example(mmd)
        nil
      rescue StandardError
        mmd
      end
      { rendered: rendered, unrenderable: unrenderable }
    end
    let(:task_today_declaration) do
      "EXAMPLE_TODAY = Date.new(#{CONFORMANCE_EXAMPLE_TODAY.year}, " \
        "#{CONFORMANCE_EXAMPLE_TODAY.month}, #{CONFORMANCE_EXAMPLE_TODAY.day})"
    end
    # Duplicated render inputs must drift loudly here instead of blaming every
    # checked-in SVG as stale.
    let(:task_source) { example_task_source }

    it "has example sources to render" do
      # 53 is today's .mmd count under examples/; this guard catches
      # sources vanishing.
      expect(CONFORMANCE_EXAMPLE_SOURCES.size).to be >= 53
    end

    it "uses the generation task date" do
      expect(task_source).to include(task_today_declaration)
    end

    # Match the expression so a redundant local assignment is unnecessary.
    it "uses the generation task theme default" do
      expect(task_source)
        .to include("metadata[\"theme\"] || \"#{CONFORMANCE_EXAMPLE_THEME}\"")
    end

    it "uses the conformance gate named unrenderable examples" do
      task_source = example_task_source
      sources = unrenderable_example_source_lines
      declaration = expected_unrenderable_declaration(sources)

      expect(task_source).to include(declaration)
    end

    # Both directions. Asking only "does each source have an SVG" leaves the
    # other half unasked: delete or rename a source and its old SVG stays
    # tracked and stays conformant, so every assertion here goes on passing
    # while the repo carries a picture of nothing. The generate task cannot
    # catch it either — it walks sources, so a file with no source is never
    # visited.
    it "has an SVG for every source and none without one" do
      checked_in = CONFORMANCE_EXAMPLE_SVGS.map { |svg| relative(svg) }

      expect(checked_in).to match_array(expected_svgs)
    end

    it "renders every source except the ones named as unsupported" do
      expect(example_rendering.fetch(:unrenderable).map { |mmd| relative(mmd) })
        .to match_array(CONFORMANCE_UNRENDERABLE_EXAMPLES)
    end

    it "renders nonempty example output" do
      expect(example_rendering.fetch(:rendered).values.map(&:empty?))
        .to all(be(false))
    end

    it "renders SVG-shaped example documents" do
      flags = example_rendering.fetch(:rendered).values.map do |svg|
        svg_document?(svg)
      end
      expect(flags).to all(be(true))
    end

    it "has checked in exactly what the renderer produces today" do
      observed = example_comparison
      expect([observed.fetch(:compared), observed.fetch(:stale)])
        .to eq([observed.fetch(:expected_count), []]),
            -> { stale_example_message(observed) }
    end
  end
end
