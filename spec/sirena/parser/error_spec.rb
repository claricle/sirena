# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/error"

RSpec.describe Sirena::Parser::Error, :aggregate_failures do
  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses a simple error diagram" do
      source = "error"

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Error)
      expect(diagram.message).to be_nil
    end

    it "refuses a message after the keyword, as Mermaid does" do
      expect { parser.parse("Error Diagrams") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "validates diagram structure" do
      source = "error"

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
    end
  end

  # :corpus - sweeps the whole fixture directory and only asserts
  # `not_to raise_error`. Runs in `spec:corpus`, isolated from the
  # coverage-collecting `spec:unit` run: see .simplecov and
  # tasks/coverage.rake.
  describe "fixture files", :corpus do
    oracle_rejected = %w[errordiagram_spec-34805ce6.mmd]

    Dir.glob("spec/mermaid/error/*.mmd").each do |fixture_file|
      name = File.basename(fixture_file)
      next if oracle_rejected.include?(name)

      it "parses #{name}" do
        source = File.read(fixture_file)

        expect { parser.parse(source) }.not_to raise_error
      end
    end

    it "refuses the oracle-rejected fixture errordiagram_spec-34805ce6" do
      source = File.read("spec/mermaid/error/#{oracle_rejected.first}")

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end
end
