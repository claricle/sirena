# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "yaml"

# Finds a real .mmd source for each registered diagram type.
module SvgRegistrySources
  module_function

  def corpus_root
    @corpus_root ||= SpecSupport::RepositoryPaths.path("spec/mermaid")
  end

  def fixtures_root
    @fixtures_root ||= SpecSupport::RepositoryPaths.path("spec/fixtures")
  end

  def verdicts
    @verdicts ||= YAML.safe_load_file(File.join(corpus_root,
                                                "corpus-verdicts.yml"))
      .to_h do |entry|
      [entry["case"], entry["verdict"]]
    end
  end

  def corpus_cases
    @corpus_cases ||= Dir.glob(File.join(corpus_root, "*", "*.mmd"))
      .map { |path| [path, File.read(path)] }
  end

  def missing_source_message(type)
    "no source available for #{type} -- see the source-existence example"
  end

  # A real .mmd source for +type+, never typed by hand here: prefers the
  # shared contract fixture, then spec/fixtures/<type>/input.mmd, else the
  # first spec/mermaid corpus
  # case whose CONTENT matches the type's Engine::DIAGRAM_TYPE_PATTERNS
  # entry (not its directory name -- several corpus directories hold the
  # same diagram under a different extraction-batch name). Prefers a
  # corpus-verdicts.yml "valid" case, then one not marked "invalid", so a
  # type is never skipped for want of an oracle verdict.
  def find_source(type)
    fixture_source(type) || corpus_source(type)
  end

  def fixture_source(type)
    candidates = [File.join(fixtures_root, "contract", "#{type}.mmd"),
                  File.join(fixtures_root, type.to_s, "input.mmd")]
    path = candidates.find { |candidate| File.exist?(candidate) }
    path && File.read(path)
  end

  def corpus_source(type)
    pattern = Sirena::Engine::DIAGRAM_TYPE_PATTERNS.fetch(type)
    candidates = corpus_cases.select do |_path, content|
      content.match?(pattern)
    end
    preferred_case(candidates)&.last
  end

  def preferred_case(candidates)
    candidates.find { |path, _| verdict_for(path) == "valid" } ||
      candidates.find { |path, _| verdict_for(path) != "invalid" } ||
      candidates.first
  end

  def verdict_for(path)
    verdicts[path.delete_prefix("#{corpus_root}/")]
  end
end

# Iterates every DiagramRegistry type, REXML-parses its rendered SVG, and
# asserts the root is <svg>. Catches a hand-written to_xml emitting
# malformed output or dropping the root.
RSpec.describe "SVG output for every registered diagram type" do # rubocop:disable RSpec/DescribeClass
  Sirena::DiagramRegistry.types.each do |type|
    it "has a real fixture or corpus source for #{type}" do
      message = "no contract/input fixture and no spec/mermaid corpus case " \
                "matches Engine::DIAGRAM_TYPE_PATTERNS[:#{type}] -- add one " \
                "before registering this type"

      expect(SvgRegistrySources.find_source(type)).not_to be_nil, message
    end

    it "renders #{type} as SVG that REXML parses with an <svg> root" do
      source = SvgRegistrySources.find_source(type)
      skip SvgRegistrySources.missing_source_message(type) if source.nil?

      document = REXML::Document.new(Sirena::Engine.new.render(source))

      expect(document.root.name).to eq("svg")
    end
  end
end
