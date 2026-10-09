# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/support/type_generator"

module TypeGeneratorSpecHelpers
  REPO = File.expand_path("../../..", __dir__)

  def written_paths(root)
    Dir.glob("**/*", base: root).select { |p| File.file?(File.join(root, p)) }
  end

  def defining(paths)
    paths.reject { |path| path.start_with?("spec/sirena/") }
  end
end

RSpec.describe Sirena::TypeGenerator do
  include TypeGeneratorSpecHelpers

  let(:root) { Dir.mktmpdir("type-generator") }
  let(:types) { Sirena::Notation::Mermaid::TYPES }
  let(:table) { Sirena::TypeGenerator::TYPES_FILE }
  let(:table_path) { File.join(root, table) }

  before do
    FileUtils.mkdir_p(File.dirname(table_path))
    FileUtils.cp(File.join(TypeGeneratorSpecHelpers::REPO, table), table_path)
  end

  after { FileUtils.remove_entry(root) }

  def generate(name)
    described_class.new(name, root: root, types: types).call
  end

  describe "#call" do
    let!(:written) { generate("demo") }

    it "writes the six lib files, the fixture and the TYPES edit" do
      expect(defining(written).size).to eq(8)
    end

    it "writes one spec per layer" do
      expect((written - defining(written)).size).to eq(4)
    end

    it "keeps each defining file where the card names it" do
      expect(written).to include(
        "lib/sirena/layout/demo.rb", "spec/fixtures/contract/demo.mmd"
      )
    end

    it "adds a row that detects the keyword" do
      row = '        demo: {
          pattern: /\\A\\s*demo(\\s|\\z)/i,
          keyword: "demo",
        },
'

      expect(File.read(table_path)).to include(row)
    end

    it "leaves the table valid Ruby" do
      expect { RubyVM::InstructionSequence.compile(File.read(table_path)) }
        .not_to raise_error
    end

    it "puts the row inside the table, not after it" do
      source = File.read(table_path)

      expect(source.index("demo: {")).to be < source.index("}.freeze")
    end

    it "generates files that are valid Ruby" do
      sources = written.grep(/\.rb\z/).map { |p| File.read(File.join(root, p)) }
      compile = ->(code) { RubyVM::InstructionSequence.compile(code) }

      expect { sources.each(&compile) }.not_to raise_error
    end
  end

  describe "refusals" do
    {
      "an uppercase name" => "Demo",
      "a name with a dash" => "my-chart",
      "a name starting with a digit" => "1demo",
      "an existing type" => "pie",
      "a keyword an earlier row claims" => "information",
    }.each do |label, name|
      it "refuses #{label}" do
        expect { generate(name) }.to raise_error(described_class::Error)
      end

      it "writes nothing for #{label}" do
        before = written_paths(root)
        begin
          generate(name)
        rescue described_class::Error
          nil
        end

        expect(written_paths(root)).to eq(before)
      end
    end

    it "refuses to overwrite an existing file and leaves the table alone" do
      FileUtils.mkdir_p(File.join(root, "lib/sirena/layout"))
      File.write(File.join(root, "lib/sirena/layout/demo.rb"), "mine")
      before_table = File.read(table_path)

      expect { generate("demo") }.to raise_error(described_class::Error)
      expect(File.read(table_path)).to eq(before_table)
    end
  end
end
