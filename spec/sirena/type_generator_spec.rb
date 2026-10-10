# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../tasks/support/type_generator"

module TypeGeneratorSpecHelpers
  REPO = File.expand_path("../..", __dir__)
  UNIT_NAME = "sample_unit"
  ACCEPTANCE_NAME = "demo"
  ACCEPTANCE_PATHS = [
    ".rspec",
    "lib",
    "docs/ir-type-map.md",
    "spec/spec_helper.rb",
    "spec/support",
    "spec/fixtures/contract",
    "spec/contract_spec.rb",
    "spec/sirena/notation/mermaid_ir_type_map_spec.rb",
    "spec/sirena/svg/registry_spec.rb",
  ].freeze

  def registered_row(name)
    <<~RUBY.gsub(/^(?=.)/, "        ")
      #{name}: {
        pattern: /\\A\\s*#{name}(\\s|\\z)/i,
        keyword: "#{name}",
        ir_adapter: true,
      },
    RUBY
  end

  def written_paths(root)
    Dir.glob("**/*", base: root).select { |p| File.file?(File.join(root, p)) }
  end

  def defining(paths)
    paths.reject { |path| path.start_with?("spec/sirena/") }
  end

  def suppress_refusal
    yield
  rescue Sirena::TypeGenerator::Error
    nil
  end

  def copy_acceptance_tree(destination)
    ACCEPTANCE_PATHS.each do |relative|
      source = File.join(REPO, relative)
      target = File.join(destination, relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp_r(source, target)
    end
  end

  def acceptance_specs
    generated = %w[parser diagram layout renderer].map do |layer|
      "spec/sirena/#{layer}/#{ACCEPTANCE_NAME}_spec.rb"
    end
    generated.insert(
      2,
      "spec/sirena/notation/mermaid/ir_adapters/#{ACCEPTANCE_NAME}_spec.rb",
    )
    generated + [
      "spec/contract_spec.rb",
      "spec/sirena/notation/mermaid_ir_type_map_spec.rb",
      "spec/sirena/svg/registry_spec.rb",
    ]
  end

  def run_acceptance(root)
    command = [RbConfig.ruby, Gem.bin_path("rspec-core", "rspec"),
               "--format", "progress", *acceptance_specs]
    Open3.capture2e(*command, chdir: root)
  end

  def expected_defining_paths
    [
      "lib/sirena/layout/sample_unit.rb",
      "lib/sirena/notation/mermaid/ir_adapters/sample_unit.rb",
      "spec/fixtures/contract/sample_unit.mmd",
      "docs/ir-type-map.md",
    ]
  end

  def ir_map_facts(source)
    summary = "**6 pre-positioned, 12 graph-shaped, " \
              "7 data-shaped; 25 total.**"
    [source.scan(/^\| `sample_unit` \|/).length, source.include?(summary)]
  end
end

RSpec.describe Sirena::TypeGenerator do
  include TypeGeneratorSpecHelpers

  let(:root) { Dir.mktmpdir("type-generator") }
  let(:types) { Sirena::Notation::Mermaid::TYPES }
  let(:table_path) do
    File.join(root, Sirena::TypeGenerator::TYPES_FILE)
  end
  let(:ir_map_path) do
    File.join(root, Sirena::TypeGenerator::IR_MAP_FILE)
  end

  before do
    FileUtils.mkdir_p(File.dirname(table_path))
    FileUtils.cp(
      File.join(TypeGeneratorSpecHelpers::REPO,
                Sirena::TypeGenerator::TYPES_FILE),
      table_path,
    )
    FileUtils.mkdir_p(File.dirname(ir_map_path))
    FileUtils.cp(
      File.join(TypeGeneratorSpecHelpers::REPO,
                Sirena::TypeGenerator::IR_MAP_FILE),
      ir_map_path,
    )
  end

  after { FileUtils.remove_entry(root) }

  def generate(name)
    described_class.new(name, root: root, types: types).call
  end

  describe "#call" do
    let!(:written) { generate(TypeGeneratorSpecHelpers::UNIT_NAME) }

    it "writes eight new definitions and edits both registries" do
      expect(defining(written).size).to eq(10)
    end

    it "writes one spec per layer and one for the IR adapter" do
      expect((written - defining(written)).size).to eq(5)
    end

    it "keeps each defining file where the card names it" do
      expect(written).to include(*expected_defining_paths)
    end

    it "adds a row that detects the keyword" do
      expect(File.read(table_path))
        .to include(registered_row(TypeGeneratorSpecHelpers::UNIT_NAME))
    end

    it "leaves the table valid Ruby" do
      expect { RubyVM::InstructionSequence.compile(File.read(table_path)) }
        .not_to raise_error
    end

    it "puts the row inside the table, not after it" do
      source = File.read(table_path)

      expect(source.index("sample_unit: {")).to be < source.index("}.freeze")
    end

    it "generates files that are valid Ruby" do
      sources = written.grep(/\.rb\z/).map { |p| File.read(File.join(root, p)) }
      compile = ->(code) { RubyVM::InstructionSequence.compile(code) }

      expect { sources.each(&compile) }.not_to raise_error
    end

    it "adds one stable data-shaped IR-map row and updates its counts" do
      expect(ir_map_facts(File.read(ir_map_path))).to eq([1, true])
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
        suppress_refusal { generate(name) }
        expect(written_paths(root)).to eq(before)
      end
    end

    context "when a target file already exists" do
      before do
        FileUtils.mkdir_p(File.join(root, "lib/sirena/layout"))
        File.write(File.join(root, "lib/sirena/layout/sample_unit.rb"), "mine")
      end

      it "refuses to overwrite it" do
        expect { generate(TypeGeneratorSpecHelpers::UNIT_NAME) }
          .to raise_error(described_class::Error)
      end

      it "leaves the table alone" do
        before_table = File.read(table_path)
        suppress_refusal { generate(TypeGeneratorSpecHelpers::UNIT_NAME) }
        expect(File.read(table_path)).to eq(before_table)
      end
    end
  end

  describe "generated-tree acceptance" do
    let(:copied_root) { Dir.mktmpdir("type-generator-acceptance") }

    before do
      copy_acceptance_tree(copied_root)
      described_class.new(
        TypeGeneratorSpecHelpers::ACCEPTANCE_NAME,
        root: copied_root,
        types: types,
      ).call
    end

    after { FileUtils.remove_entry(copied_root) }

    it "passes its generated specs and repository-wide type contracts" do
      output, status = run_acceptance(copied_root)

      expect([status.success?, output.include?("0 failures")])
        .to eq([true, true]), output
    end
  end
end
