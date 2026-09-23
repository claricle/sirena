# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'yaml'

# Iterates every DiagramRegistry type, REXML-parses its rendered SVG, and
# asserts the root is <svg>. Catches a hand-written to_xml emitting
# malformed output or dropping the root.
RSpec.describe 'SVG output for every registered diagram type' do # rubocop:disable RSpec/DescribeClass
  # Class methods, not `it`-closed locals and not a describe-body constant,
  # so each is memoized once across the whole type loop below.
  def self.corpus_root
    @corpus_root ||= File.expand_path('../../mermaid', __dir__)
  end

  def self.fixtures_root
    @fixtures_root ||= File.expand_path('../../fixtures', __dir__)
  end

  def self.verdicts
    @verdicts ||= YAML.safe_load_file(File.join(corpus_root, 'corpus-verdicts.yml'))
      .to_h { |entry| [entry['case'], entry['verdict']] }
  end

  def self.corpus_cases
    @corpus_cases ||= Dir.glob(File.join(corpus_root, '*', '*.mmd'))
      .map { |path| [path, File.read(path)] }
  end

  # A real .mmd source for +type+, never typed by hand here: prefers
  # spec/fixtures/<type>/input.mmd, else the first spec/mermaid corpus
  # case whose CONTENT matches the type's Engine::DIAGRAM_TYPE_PATTERNS
  # entry (not its directory name -- several corpus directories hold the
  # same diagram under a different extraction-batch name). Prefers a
  # corpus-verdicts.yml "valid" case, then one not marked "invalid", so a
  # type is never skipped for want of an oracle verdict.
  def self.find_source(type)
    fixture_path = File.join(fixtures_root, type.to_s, 'input.mmd')
    return File.read(fixture_path) if File.exist?(fixture_path)

    pattern = Sirena::Engine::DIAGRAM_TYPE_PATTERNS.fetch(type)
    candidates = corpus_cases.select { |_path, content| content.match?(pattern) }
    verdict_of = ->(path) { verdicts[path.delete_prefix("#{corpus_root}/")] }

    chosen = candidates.find { |path, _| verdict_of.call(path) == 'valid' } ||
      candidates.find { |path, _| verdict_of.call(path) != 'invalid' } ||
      candidates.first
    chosen&.last
  end

  Sirena::DiagramRegistry.types.each do |type|
    it "has a real fixture or corpus source for #{type}" do
      message = "no spec/fixtures/#{type}/input.mmd and no spec/mermaid corpus case matches " \
        "Engine::DIAGRAM_TYPE_PATTERNS[:#{type}] -- add one before registering this type"

      expect(self.class.find_source(type)).not_to be_nil, message
    end

    it "renders #{type} as SVG that REXML parses with an <svg> root" do
      source = self.class.find_source(type)
      skip "no source available for #{type} -- see the source-existence example" if source.nil?

      document = REXML::Document.new(Sirena::Engine.new.render(source))

      expect(document.root.name).to eq('svg')
    end
  end
end
