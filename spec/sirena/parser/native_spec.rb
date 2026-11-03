# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/pie"

RSpec.describe Sirena::Parser::Native do
  let(:source) { "pie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 2\n" }

  around do |example|
    previous = ENV.fetch("SIRENA_NATIVE_PARSER", nil)
    ENV.delete("SIRENA_NATIVE_PARSER")
    described_class.reset!
    example.run
  ensure
    ENV["SIRENA_NATIVE_PARSER"] = previous
    described_class.reset!
  end

  def slice_pairs(diagram)
    diagram.slices.map { |slice| [slice.label, slice.value] }
  end

  describe ".parse" do
    it "answers with a tree when the engine is present" do
      skip "parsanol engine absent" unless described_class.available?

      expect(described_class.parse(:pie, source)).to be_a(Array)
    end

    it "declines input the grammar rejects" do
      expect(described_class.parse(:pie, "pie\n  nonsense")).to be_nil
    end

    it "declines a source that is not valid UTF-8" do
      binary = "pie\n  \"\xFF\" : 1".b

      expect(described_class.parse(:pie, binary)).to be_nil
    end

    it "declines when disabled by the environment" do
      ENV["SIRENA_NATIVE_PARSER"] = "ruby"

      expect(described_class.parse(:pie, source)).to be_nil
    end
  end

  describe "with the native engine absent" do
    before do
      allow(described_class).to receive(:require).with("parsanol")
        .and_raise(LoadError)
    end

    it "reports unavailable" do
      expect(described_class.available?).to be(false)
    end

    it "still parses through the Ruby grammar" do
      diagram = Sirena::Parser::Pie.new.parse(source)

      expect(slice_pairs(diagram)).to eq([["Dogs", 3.0], ["Cats", 2.0]])
    end

    it "keeps the title on the Ruby path" do
      expect(Sirena::Parser::Pie.new.parse(source).title).to eq("Pets")
    end

    it "still raises the positioned ParseError for bad input" do
      expect { Sirena::Parser::Pie.new.parse("pie\n  nonsense") }
        .to raise_error(Sirena::Parser::ParseError, /line 2/)
    end
  end

  describe "Parser::Base#parse routing" do
    it "builds through the native builder when the engine answers" do
      skip "parsanol engine absent" unless described_class.available?

      allow(Sirena::Parser::Native::Builders::Pie).to receive(:new)
        .and_return(instance_double(Sirena::Parser::Native::Builders::Pie,
                                    apply: :native_diagram))

      expect(Sirena::Parser::Pie.new.parse(source)).to eq(:native_diagram)
    end

    it "falls back to the Ruby path when the native builder declines" do
      skip "parsanol engine absent" unless described_class.available?

      diagram = Sirena::Parser::Pie.new.parse("pie\n  accTitle:\n  \"a\" : 1")

      expect(diagram.acc_title).to eq("[]")
    end
  end
end
