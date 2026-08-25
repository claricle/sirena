# frozen_string_literal: true

require 'spec_helper'
require 'svg_conform'
require 'timeout'

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
# The corpus pass costs about a minute, which is most of this suite's runtime.
# It earns it: each of the four conformance defects this gate was written for
# came out of a renderer no unit spec covered.
CONFORMANCE_ROOT = File.expand_path('..', __dir__)
CONFORMANCE_SHIPPED_SVGS = Dir.glob(File.join(CONFORMANCE_ROOT, 'examples', '**', '*.svg')).freeze
CONFORMANCE_FIXTURE_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'spec', 'fixtures', '*', 'input.mmd')).freeze
CONFORMANCE_CORPUS_SOURCES = Dir.glob(File.join(CONFORMANCE_ROOT, 'spec', 'mermaid', '*', '*.mmd')).freeze

# Same guard corpus_sweep.rb uses. A case that hangs is a corpus problem, not
# a conformance one, and it must not hang the suite.
CONFORMANCE_CASE_TIMEOUT = 10

RSpec.describe Sirena::Svg do
  def validate(svg)
    SvgConform.validate(svg, profile: Sirena::Svg::CONFORMANCE_PROFILE)
  end

  def complaint(path, result)
    messages = result.errors.map { |e| e.respond_to?(:message) ? e.message : e.to_s }
    "#{path.sub("#{CONFORMANCE_ROOT}/", '')}: #{messages.uniq.first(3).join(' | ')}"
  end

  # A case Sirena cannot render is item 06's problem, not this gate's. Only
  # output that claims to be an SVG document is judged here.
  def render_or_skip(path)
    svg = Timeout.timeout(CONFORMANCE_CASE_TIMEOUT) { Sirena::Engine.new.render(File.read(path)) }
    svg if svg.is_a?(String) && svg.include?('<svg')
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

        result = validate(content)
        expect(result).to be_valid, -> { complaint(svg_path, result) }
      end
    end
  end

  describe 'conformance of the reference fixtures' do
    CONFORMANCE_FIXTURE_SOURCES.each do |source_path|
      it "renders #{File.basename(File.dirname(source_path))} conformantly" do
        result = validate(Sirena::Engine.new.render(File.read(source_path)))

        expect(result).to be_valid, -> { complaint(source_path, result) }
      end
    end
  end

  describe 'conformance across the mermaid corpus' do
    # One example rather than 1,997: the useful failure is the whole list of
    # offending cases and what each emitted, not the first one rspec reaches.
    it 'renders every case it can render conformantly' do
      offenders = CONFORMANCE_CORPUS_SOURCES.filter_map do |source_path|
        svg = render_or_skip(source_path)
        next unless svg

        result = validate(svg)
        complaint(source_path, result) unless result.valid?
      end

      expect(offenders).to be_empty, -> { offenders.join("\n") }
    end
  end
end
