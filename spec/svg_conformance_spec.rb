# frozen_string_literal: true

require 'spec_helper'
require 'svg_conform'
require 'date'
require 'rexml/document'
require 'timeout'
require 'yaml'

# The gate. Sirena's SVG is embedded straight into Metanorma documents, so
# "renders something" is not the bar — the document has to be conformant, and
# it has to stay conformant when a renderer changes.
#
# Three populations, because they fail for different reasons:
#
#   * The SVGs under examples/ ship inside the gem. The gemspec packages
#     whatever `git ls-files` returns, so a stale or empty file there goes out
#     to every user. These are checked as files, not as renders.
#   * The reference fixtures are the per-type shape the rest of the suite
#     already trusts.
#   * The mermaid corpus is the wide net: 1,997 sources across every diagram
#     type, and the only place an attribute a single renderer emits shows up.
#
# The corpus pass renders all 1,997 sources and validates every document they
# produce, with a floor guarding the rendered population. Worth every one of
# them: each of the four conformance defects this gate was written for came out
# of a renderer no unit spec covered.
CONFORMANCE_ROOT = File.expand_path('..', __dir__)

# Asked of the gemspec rather than globbed, because the gemspec is what
# decides. It packages what `git ls-files` returns minus its own exclusions,
# so an untracked SVG in the working copy is not something the gem ships and
# validating it would report on a file no user receives.
CONFORMANCE_SHIPPED_SVGS =
  Gem::Specification.load(File.join(CONFORMANCE_ROOT, 'sirena.gemspec'))
    .files.grep(%r{\Aexamples/.*\.svg\z})
    .map { |f| File.join(CONFORMANCE_ROOT, f) }
    .freeze
CONFORMANCE_FIXTURE_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'spec', 'fixtures', '*', 'input.mmd')).freeze
CONFORMANCE_CORPUS_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'spec', 'mermaid', '*', '*.mmd')).freeze
CONFORMANCE_EXAMPLE_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'examples', '*', '*.mmd')).freeze

# How many corpus cases render to a document today. A floor rather than the
# exact figure, because item 06 raises it and this gate must not stand in the
# way — but a renderer that starts raising for every input takes its whole
# type out of the population, and an offender list over what survives would
# stay green while measuring less. Ratchet it up when it rises.
#
# 736 measured 2026-08-27 with `bundle exec ruby scripts/corpus_sweep.rb`,
# which counts the same population by the same criterion.
CONFORMANCE_RENDERED_FLOOR = 736

# The example sources Sirena cannot parse yet, so they ship no SVG. Named
# rather than counted: a NEW source falling out of the shipped set is a
# regression, and a glob over whatever happens to exist cannot see one.
CONFORMANCE_UNRENDERABLE_EXAMPLES = [
  'gantt/01-simple-timeline.beta.mmd',
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

  # svg_conform 0.2.1 reports on the elements and attributes it can find and
  # never parses: measured against the real checker, it answers `valid?` for
  # an unclosed tag, a mismatched pair, a raw `&`, a missing `</svg>` and for
  # trailing junk after the root. So conformance alone would keep this gate
  # green on output no XML parser would accept, which is the one thing a
  # document embedded in Metanorma may not be.
  #
  # REXML is the whole check because Escaping escapes every `&` and strips
  # the code points XML forbids, so Sirena cannot emit the undeclared entity
  # REXML is lenient about.
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

  describe 'conformance of the SVGs the gem ships' do
    it 'ships some' do
      expect(CONFORMANCE_SHIPPED_SVGS).not_to be_empty
    end

    CONFORMANCE_SHIPPED_SVGS.each do |svg_path|
      it "#{svg_path.sub("#{CONFORMANCE_ROOT}/", '')} is conformant" do
        content = File.read(svg_path)

        # A zero-byte file passed every check this repo had: nothing to parse
        # is nothing to reject, and the gemspec ships it anyway.
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
    it 'renders every case it can render conformantly' do
      rendered = 0
      offenders = CONFORMANCE_CORPUS_SOURCES.filter_map do |source_path|
        svg = render_or_skip(source_path)
        next unless svg

        rendered += 1
        malformed = parse_error(svg)
        next "#{source_path.sub("#{CONFORMANCE_ROOT}/", '')}: not well-formed: #{malformed}" if malformed

        result = validate(svg)
        complaint(source_path, result) unless result.valid?
      end

      # Checked first: an empty offender list means nothing until the
      # population it was drawn from is known to be intact.
      expect(rendered).to be >= CONFORMANCE_RENDERED_FLOOR
      expect(offenders).to be_empty, -> { offenders.join("\n") }
    end
  end

  # The gate above judges the SVGs that happen to be on disk, which is not
  # the same question. Presence proves nothing about whether the renderer
  # still works, or whether what ships is what the renderer produces today.
  # Both are rendered here rather than looked for.
  describe 'the examples the gem ships' do
    # The same inputs examples.rake uses. The date is pinned there because
    # gantt and timeline place bars relative to today, so an unpinned render
    # differs from identical source every day.
    def render_example(mmd_path)
      metadata_path = mmd_path.sub(/\.mmd\z/, '.yml')
      metadata = File.exist?(metadata_path) ? YAML.load_file(metadata_path) : {}
      # Unlike the corpus's Engine call, this mirrors examples.rake's theme/today arguments.
      Sirena.render(File.read(mmd_path), theme: metadata['theme'] || CONFORMANCE_EXAMPLE_THEME,
                                         today: CONFORMANCE_EXAMPLE_TODAY)
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
      task_source = File.read(File.join(CONFORMANCE_ROOT, 'lib', 'tasks', 'examples.rake'))

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
      task_source = File.read(File.join(CONFORMANCE_ROOT, 'lib', 'tasks', 'examples.rake'))
      sources = CONFORMANCE_UNRENDERABLE_EXAMPLES.map { |source| "  '#{source}'" }.join(",\n")

      expect(task_source).to include(
        "EXPECTED_UNRENDERABLE_SOURCES = [\n#{sources}\n].freeze"
      )
    end

    # Both directions. Asking only "does each source ship an SVG" leaves the
    # other half unasked: delete or rename a source and its old SVG stays
    # tracked, stays packaged, and stays conformant, so every assertion here
    # goes on passing while the gem ships a picture of nothing. The generate
    # task cannot catch it either — it walks sources, so a file with no
    # source is never visited.
    it 'packages an SVG for every source and none without one' do
      packaged = CONFORMANCE_SHIPPED_SVGS.map { |svg| relative(svg) }

      expect(packaged).to match_array(expected_svgs)
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

    it 'ships exactly what the renderer produces today' do
      compared = 0
      stale = CONFORMANCE_EXAMPLE_SOURCES.filter_map do |mmd|
        rendered = begin
          render_example(mmd)
        rescue StandardError
          next
        end

        compared += 1
        svg_path = mmd.sub(/\.mmd\z/, '.svg')
        next relative(svg_path) unless CONFORMANCE_SHIPPED_SVGS.include?(svg_path)

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
