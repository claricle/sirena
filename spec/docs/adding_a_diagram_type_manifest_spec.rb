# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../tasks/support/type_generator"

module AddingADiagramTypeManifest
  GUIDE = File.expand_path("../../docs/adding-a-diagram-type.adoc", __dir__)
  TYPE_TASK = File.expand_path("../../tasks/type.rake", __dir__)
  CORPUS_TASK = File.expand_path("../../tasks/corpus.rake", __dir__)
  SHARED_EXAMPLES = File.expand_path(
    "../support/diagram_type_examples.rb", __dir__
  )
  GENERATED_FILES = %r{
    //\ tag::generated-files\[\]\n(?<manifest>.*?)
    //\ end::generated-files\[\]
  }mx
  GUIDE_SURFACES = [
    "bundle exec rake 'type:new[demo]'",
    "bundle exec rake 'corpus[pie]'",
    "bundle exec rake 'corpus[pie,valid]'",
    "bundle exec rspec spec/contract_spec.rb -e demo",
    "spec/support/diagram_type_examples.rb",
  ].freeze
end

RSpec.describe AddingADiagramTypeManifest do
  let(:guide) { File.read(described_class::GUIDE) }
  let(:documented_manifest) do
    section = guide.match(described_class::GENERATED_FILES)[:manifest]
    section.scan(/^\* `([^`]+)`$/).flatten
  end
  let(:generated_manifest) do
    Dir.mktmpdir("documented-type-generator") do |root|
      types_path = File.join(root, Sirena::TypeGenerator::TYPES_FILE)
      FileUtils.mkdir_p(File.dirname(types_path))
      FileUtils.cp(Sirena::TypeGenerator::TYPES_FILE, types_path)
      FileUtils.mkdir_p(File.join(root, "docs"))
      FileUtils.cp(Sirena::TypeGenerator::IR_MAP_FILE, File.join(root, "docs"))
      Sirena::TypeGenerator.new(
        "doc_demo", root: root, types: Sirena::Notation::Mermaid::TYPES
      ).call.map { |path| path.gsub("doc_demo", "<type>") }
    end
  end
  let(:documented_surface_facts) do
    guide_surfaces_match = described_class::GUIDE_SURFACES.all? do |surface|
      guide.include?(surface)
    end
    [
      File.read(described_class::TYPE_TASK).include?("task :new, [:name]"),
      File.read(described_class::CORPUS_TASK)
        .include?("task :corpus, %i[type filter]"),
      File.read(described_class::SHARED_EXAMPLES)
        .include?('RSpec.shared_examples "a diagram type"'),
      guide_surfaces_match,
    ]
  end
  let(:corpus_contract_facts) do
    commands = guide.lines.grep(/\Abundle exec /)
    [
      File.read(described_class::CORPUS_TASK)
        .include?('return :valid if filter == "valid"'),
      guide.include?("`valid` is the only supported filter"),
      guide.include?("spec/mermaid/<type>/<case>.mmd -o /dev/null"),
      commands.none? { |line| line.include?("--failing") },
      commands.none? { |line| line.include?("corpus[pie,failing]") },
    ]
  end

  it "is a buildable AsciiDoc page" do
    facts = [
      guide.start_with?("---\nlayout: default\ntitle: Adding a diagram type\n"),
      guide.include?("permalink: /adding-a-diagram-type/\n---\n"),
    ]

    expect(facts).to all(be(true))
  end

  it "lists exactly the paths the current generator writes" do
    expect(documented_manifest).to eq(generated_manifest)
  end

  it "documents the current task and shared-contract surfaces" do
    expect(documented_surface_facts).to all(be(true))
  end

  it "documents the corpus filter and single-case reproduction exactly" do
    expect(corpus_contract_facts).to all(be(true))
  end
end
