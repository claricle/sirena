# frozen_string_literal: true

require "spec_helper"
require "rake"

load File.expand_path("../../tasks/corpus.rake", __dir__) unless defined?(Sirena::Corpus)

RSpec.describe Sirena::CorpusTypeNames do
  let(:table) { described_class::DIRECTORIES }

  describe "the table" do
    it "names exactly the directories under spec/mermaid" do
      expect(table.keys).to match_array(Sirena::Corpus.types)
    end

    it "maps every directory to a registered type or nil" do
      unregistered = table.values.compact.uniq.reject do |type|
        Sirena::DiagramRegistry.registered?(type)
      end

      expect(unregistered).to eq([])
    end

    it "leaves no registered type without a corpus directory" do
      covered = table.values.compact.uniq

      expect(Sirena::DiagramRegistry.types - covered).to eq([])
    end

    it "is frozen" do
      expect(table).to be_frozen
    end
  end

  describe "the readers" do
    it "gives the rake task the registry type of a directory" do
      expect(Sirena::Corpus.registry_type("gitgraph")).to eq(:git_graph)
    end

    it "gives the registry the directories of a type" do
      expect(Sirena::DiagramRegistry.corpus_directories(:git_graph))
        .to eq(%w[git gitgraph])
    end

    it "reads one table: a seeded wrong entry changes both readers" do
      stub_const("#{described_class}::DIRECTORIES",
                 table.merge("gitgraph" => :pie).freeze)

      expect([Sirena::Corpus.registry_type("gitgraph"),
              Sirena::DiagramRegistry.corpus_directories(:git_graph)])
        .to eq([:pie, %w[git]])
    end

    it "resolves a directory with no registered type to nil" do
      expect(Sirena::Corpus.registry_type("unknown")).to be_nil
    end
  end
end
