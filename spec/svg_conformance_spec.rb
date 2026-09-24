# frozen_string_literal: true

require 'spec_helper'
require 'svg_conform'
require 'date'
require 'rexml/document'
require 'timeout'
require 'yaml'

# The gate: output must stay svg_conform-conformant, not just "renders
# something". Three populations checked differently because they fail
# differently -- examples/ SVGs as on-disk FILES globbed off disk (intended
# to feed the docs site once TODO.foundation/15 wires that build up; no
# workflow ships them to a reader today), reference fixtures as the per-type
# shape, and the 1,997-source mermaid corpus as the wide net (floor-guarded,
# not counted -- see CONFORMANCE_RENDERABLE_FILE below).
CONFORMANCE_ROOT = File.expand_path('..', __dir__)

# Globbed directly, not asked of the gemspec: since D6 (sirena.gemspec's
# `files` became a lib+exe allowlist), examples/ no longer ships inside the
# gem, but the on-disk SVGs are still meant to feed the docs site build
# (per TODO.foundation/15, not yet wired) and still need a conformance guard.
CONFORMANCE_EXAMPLE_SVGS =
  (Dir.glob(File.join(CONFORMANCE_ROOT, 'examples', '*.svg')) +
   Dir.glob(File.join(CONFORMANCE_ROOT, 'examples', '*', '*.svg'))).freeze
CONFORMANCE_FIXTURE_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'spec', 'fixtures', '*', 'input.mmd')).freeze
CONFORMANCE_CORPUS_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'spec', 'mermaid', '*', '*.mmd')).freeze
CONFORMANCE_EXAMPLE_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'examples', '*', '*.mmd')).freeze

# Which corpus cases render today, by NAME not count -- a count can't see
# a regressing case swap places with a gaining one. A floor, not an
# equality: additions are free (item 06 raises this weekly), only a case
# that STOPS rendering fails it.
#
# Regenerate after a real gain with
# `CONFORMANCE_WRITE_RENDERABLE=1 bundle exec rspec spec/svg_conformance_spec.rb`.
CONFORMANCE_RENDERABLE_FILE = File.join(CONFORMANCE_ROOT, 'spec', 'mermaid', 'corpus-renderable.txt')

# The size the baseline itself must not fall below. It guards the guard: an
# emptied or truncated list would make the subset check pass against nothing.
# Same population `scripts/corpus_sweep.rb` counts by the same criterion.
#
# Dropped from 898 to 895, for two different reasons.
#
# mindmap/031 ("multiple roots are illegal") and mindmap/032 ("real root in
# wrong place") used to "render" by silently dropping the true root and its
# whole subtree when a second level-zero node appeared. Real mermaid rejects
# both (`mermaid.parse` on 11.12.0 raises "There can be only one root."), so
# Sirena now correctly raising ParseError for them is a correctness win, not
# a coverage loss.
#
# mindmap/014 is different: it is `root(\n  The root\n)`, a single node
# using round-shape syntax with its text on its own line. Real mermaid
# parses that as ONE node (verified via mermaid's own db on 11.12.0: one
# node, id "root", descr "The root", no children) -- Sirena should render
# it, not reject it. The grammar has no round-shape `(text)` rule and treats
# each physical line as its own node, so it produces three fake level-0
# siblings and the multiple-roots guard above (correct for 031/032) fires
# on this case too. That guard did not regress; the gap is round-shape and
# multi-line node text, which Sirena never supported before this diff
# either (main silently mis-split it into a 2-node tree that happened to
# still look SVG-shaped). Backlogged, not fixed here -- fixing it means
# multi-line node grammar support, out of scope for this bucket.
CONFORMANCE_RENDERED_FLOOR = 895

# The example sources Sirena cannot parse yet, so they have no checked-in
# SVG. Named rather than counted: a NEW source falling out of the checked-in
# set is a regression, and a glob over whatever happens to exist cannot see
# one.
CONFORMANCE_UNRENDERABLE_EXAMPLES = [
  'packet/01-basic-packet.beta.mmd'
].freeze

# Same guard corpus_sweep.rb uses. A case that hangs is a corpus problem, not
# a conformance one, and it must not hang the suite.
CONFORMANCE_CASE_TIMEOUT = 10
CONFORMANCE_EXAMPLE_TODAY = Date.new(2026, 1, 1)
CONFORMANCE_EXAMPLE_THEME = 'default'

RSpec.describe Sirena::Svg do
  def validate(svg)
    SvgConform.validate(svg, profile: Sirena::Svg::CONFORMANCE_PROFILE)
  end

  # Needed alongside svg_conform, not redundant with it: svg_conform never
  # parses, so it answers `valid?` true for an unclosed tag, a mismatched
  # pair, a raw `&`, a missing `</svg>` -- don't drop this assuming
  # conformance alone catches malformed XML.
  #
  # @return [String, nil] the parse error, or nil when the document parses
  def parse_error(svg)
    REXML::Document.new(svg)
    nil
  rescue REXML::ParseException => e
    e.message.lines.first.to_s.strip
  end

  def complaint(path, result)
    messages = (result.errors + result.validity_errors).map(&:message).uniq
    summary = messages.first(3).join(' | ')
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
    path.sub("#{File.join(CONFORMANCE_ROOT, 'spec', 'mermaid')}/", '')
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
      Sirena::Engine.new.render(File.read(path), today: CONFORMANCE_EXAMPLE_TODAY)
    end
    svg if svg_document?(svg)
  rescue StandardError
    nil
  end

  describe 'conformance of the checked-in example SVGs' do
    it 'has some' do
      expect(CONFORMANCE_EXAMPLE_SVGS).not_to be_empty
    end

    CONFORMANCE_EXAMPLE_SVGS.each do |svg_path|
      it "#{svg_path.sub("#{CONFORMANCE_ROOT}/", '')} is conformant" do
        content = File.read(svg_path)

        # A zero-byte file passed every check this repo had: nothing to parse
        # is nothing to reject, and the docs site is meant to read it once
        # TODO.foundation/15 wires that build up.
        expect(content).not_to be_empty

        malformed = parse_error(content)
        expect(malformed).to be_nil,
                             -> { "#{svg_path.sub("#{CONFORMANCE_ROOT}/", '')}: #{malformed}" }

        result = validate(content)
        expect(result).to be_valid, -> { complaint(svg_path, result) }
      end
    end
  end

  describe 'conformance of the reference fixtures' do
    it 'has reference fixtures to render' do
      expect(CONFORMANCE_FIXTURE_SOURCES).not_to be_empty
    end

    CONFORMANCE_FIXTURE_SOURCES.each do |source_path|
      it "renders #{File.basename(File.dirname(source_path))} conformantly" do
        svg = Sirena::Engine.new.render(File.read(source_path))

        malformed = parse_error(svg)
        expect(malformed).to be_nil,
                             -> { "#{source_path.sub("#{CONFORMANCE_ROOT}/", '')}: #{malformed}" }

        result = validate(svg)
        expect(result).to be_valid, -> { complaint(source_path, result) }
      end
    end
  end

  describe 'conformance across the mermaid corpus' do
    # One example rather than 1,997: the useful failure is the whole list of
    # offending cases and what each emitted, not the first one rspec reaches.
    #
    # One example rather than two, as well. Checking the baseline's own
    # integrity somewhere else did not work: rspec randomises order, so the
    # render could run first, regenerate over a truncated list, and leave that
    # check reading the file it had just repaired. Everything that reads,
    # judges or writes the baseline happens here, in this order.
    it 'renders every case it can render conformantly' do
      # Read and judged before anything is rendered or written. An emptied or
      # truncated list would make the subset check below pass against nothing,
      # and regenerating first would compare the new list against itself.
      baseline = baseline_renderable
      expect(baseline.size).to be >= CONFORMANCE_RENDERED_FLOOR
      expect(baseline.uniq).to eq(baseline)

      rendered = []
      offenders = CONFORMANCE_CORPUS_SOURCES.filter_map do |source_path|
        svg = render_or_skip(source_path)
        next unless svg

        rendered << corpus_name(source_path)
        malformed = parse_error(svg)
        next "#{source_path.sub("#{CONFORMANCE_ROOT}/", '')}: not well-formed: #{malformed}" if malformed

        result = validate(svg)
        complaint(source_path, result) unless result.valid?
      end

      # Checked first: an empty offender list means nothing until the
      # population it was drawn from is known to be intact. By name, because a
      # count stays put when one case regresses and another gains.
      lost = baseline - rendered
      expect(lost).to be_empty,
                      -> { "stopped rendering, so nothing checked them: #{lost.sort.join(', ')}" }
      expect(offenders).to be_empty, -> { offenders.join("\n") }

      # Written last, and only once every assertion above has held, so
      # regenerating can record a gain but never quietly accept a loss or
      # launder a damaged list.
      write_renderable(rendered) if ENV['CONFORMANCE_WRITE_RENDERABLE']
    end
  end

  # The gate above judges the SVGs that happen to be on disk, which is not
  # the same question. Presence proves nothing about whether the renderer
  # still works, or whether what is checked in is what the renderer produces
  # today. Both are rendered here rather than looked for.
  describe 'the checked-in examples' do
    # The same inputs examples.rake uses. The date is pinned there because
    # gantt and timeline place bars relative to today, so an unpinned render
    # differs from identical source every day.
    def render_example(mmd_path)
      metadata_path = mmd_path.sub(/\.mmd\z/, '.yml')
      metadata = File.exist?(metadata_path) ? YAML.load_file(metadata_path) : {}
      # Same cap as render_or_skip, and for the same reason: a pathological
      # source must fail this example, not hang the whole suite.
      Timeout.timeout(CONFORMANCE_CASE_TIMEOUT) do
        # Unlike the corpus's Engine call, this mirrors examples.rake's theme/today arguments.
        Sirena.render(File.read(mmd_path), theme: metadata['theme'] || CONFORMANCE_EXAMPLE_THEME,
                                           today: CONFORMANCE_EXAMPLE_TODAY)
      end
    end

    def relative(path)
      path.sub("#{CONFORMANCE_ROOT}/examples/", '')
    end

    # Every source that is not named unrenderable owes exactly one SVG.
    def expected_svgs
      (CONFORMANCE_EXAMPLE_SOURCES.map { |mmd| relative(mmd) } -
        CONFORMANCE_UNRENDERABLE_EXAMPLES).map { |mmd| mmd.sub(/\.mmd\z/, '.svg') }
    end

    it 'has example sources to render' do
      # 53 is today's .mmd count under examples/; this guard catches sources vanishing.
      expect(CONFORMANCE_EXAMPLE_SOURCES.size).to be >= 53
    end

    # Duplicated render inputs must drift loudly here instead of blaming every
    # checked-in SVG as stale.
    it 'uses the generation task rendering defaults' do
      task_source = File.read(File.join(CONFORMANCE_ROOT, 'tasks', 'example_tasks.rb'))

      expect(task_source).to include(
        "EXAMPLE_TODAY = Date.new(#{CONFORMANCE_EXAMPLE_TODAY.year}, " \
        "#{CONFORMANCE_EXAMPLE_TODAY.month}, #{CONFORMANCE_EXAMPLE_TODAY.day})"
      )
      # The expression, not the whole assignment: pinning the statement made the
      # task keep a redundant local just to satisfy this line.
      expect(task_source)
        .to include("metadata['theme'] || '#{CONFORMANCE_EXAMPLE_THEME}'")
    end

    it 'uses the conformance gate named unrenderable examples' do
      task_source = File.read(File.join(CONFORMANCE_ROOT, 'tasks', 'example_tasks.rb'))
      sources = CONFORMANCE_UNRENDERABLE_EXAMPLES.map { |source| "  '#{source}'" }.join(",\n")

      expect(task_source).to include(
        "EXPECTED_UNRENDERABLE_SOURCES = [\n#{sources}\n].freeze"
      )
    end

    # Both directions. Asking only "does each source have an SVG" leaves the
    # other half unasked: delete or rename a source and its old SVG stays
    # tracked and stays conformant, so every assertion here goes on passing
    # while the repo carries a picture of nothing. The generate task cannot
    # catch it either — it walks sources, so a file with no source is never
    # visited.
    it 'has an SVG for every source and none without one' do
      checked_in = CONFORMANCE_EXAMPLE_SVGS.map { |svg| relative(svg) }

      expect(checked_in).to match_array(expected_svgs)
    end

    it 'renders every source except the ones named as unsupported' do
      rendered = {}
      unrenderable = CONFORMANCE_EXAMPLE_SOURCES.filter_map do |mmd|
        rendered[mmd] = render_example(mmd)
        nil
      rescue StandardError
        mmd
      end

      rendered.each_value do |svg|
        expect(svg).not_to be_empty
        expect(svg_document?(svg)).to be(true)
      end
      expect(unrenderable.map { |mmd| relative(mmd) })
        .to match_array(CONFORMANCE_UNRENDERABLE_EXAMPLES)
    end

    it 'has checked in exactly what the renderer produces today' do
      compared = 0
      stale = CONFORMANCE_EXAMPLE_SOURCES.filter_map do |mmd|
        rendered = begin
          render_example(mmd)
        rescue StandardError
          next
        end

        compared += 1
        svg_path = mmd.sub(/\.mmd\z/, '.svg')
        next relative(svg_path) unless CONFORMANCE_EXAMPLE_SVGS.include?(svg_path)

        relative(svg_path) unless File.read(svg_path) == rendered
      end

      # Checked first, and here rather than only in the example above: a
      # source that stops rendering is skipped by the rescue, and an empty
      # stale list says nothing until every source that is not named
      # unrenderable is known to have been compared.
      expect(compared)
        .to eq(CONFORMANCE_EXAMPLE_SOURCES.size - CONFORMANCE_UNRENDERABLE_EXAMPLES.size)
      expect(stale).to be_empty,
                       -> { "not tracked, or not what the renderer produces: #{stale.join(', ')}" }
    end
  end
end
