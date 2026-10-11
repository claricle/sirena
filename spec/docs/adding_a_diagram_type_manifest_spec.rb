# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../tasks/support/type_generator"

module AddingADiagramTypeManifestSpecHelpers
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

  def documented_manifest(guide)
    section = guide.match(GENERATED_FILES)[:manifest]
    section.scan(/^\* `([^`]+)`$/).flatten
  end

  def generated_manifest(root)
    types_path = File.join(root, Sirena::TypeGenerator::TYPES_FILE)
    FileUtils.mkdir_p(File.dirname(types_path))
    FileUtils.cp(Sirena::TypeGenerator::TYPES_FILE, types_path)
    FileUtils.mkdir_p(File.join(root, "docs"))
    FileUtils.cp(Sirena::TypeGenerator::IR_MAP_FILE, File.join(root, "docs"))
    Sirena::TypeGenerator.new(
      "doc_demo", root: root, types: Sirena::Notation::Mermaid::TYPES
    ).call
  end
end

RSpec.describe AddingADiagramTypeManifestSpecHelpers do
  include described_class

  let(:guide) { File.read(described_class::GUIDE) }

  it "is a buildable AsciiDoc page" do
    expect(guide).to start_with(
      "---\nlayout: default\ntitle: Adding a diagram type\n",
    )
    expect(guide).to include("permalink: /adding-a-diagram-type/\n---\n")
  end

  it "lists exactly the paths the current generator writes" do
    Dir.mktmpdir("documented-type-generator") do |root|
      generated = generated_manifest(root)
        .map { |path| path.gsub("doc_demo", "<type>") }

      expect(documented_manifest(guide)).to eq(generated)
    end
  end

  it "documents the current task and shared-contract surfaces" do
    expect(File.read(described_class::TYPE_TASK))
      .to include("task :new, [:name]")
    expect(File.read(described_class::CORPUS_TASK))
      .to include("task :corpus, %i[type filter]")
    expect(File.read(described_class::SHARED_EXAMPLES))
      .to include('RSpec.shared_examples "a diagram type"')
    expect(guide).to include(
      "bundle exec rake 'type:new[demo]'",
      "bundle exec rake 'corpus[pie]'",
      "bundle exec rake 'corpus[pie,valid]'",
      "bundle exec rspec spec/contract_spec.rb -e demo",
      "spec/support/diagram_type_examples.rb",
    )
  end

  it "documents the corpus filter and single-case reproduction exactly" do
    corpus_task = File.read(described_class::CORPUS_TASK)

    expect(corpus_task).to include('return :valid if filter == "valid"')
    expect(guide).to include(
      "`valid` is the only supported filter",
      "spec/mermaid/<type>/<case>.mmd -o /dev/null",
    )
    commands = guide.lines.grep(/\Abundle exec /)
    expect(commands).not_to include(satisfy { |line| line.include?("--failing") })
    expect(commands).not_to include(satisfy do |line|
      line.include?("corpus[pie,failing]")
    end)
  end
end
