# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::CorpusTypeNames do
  include CorpusRakeProbe

  let(:table) { described_class::DIRECTORIES }
  let(:rake_answers) { corpus_rake_answers }

  describe "the table" do
    it "names exactly the corpus directories the rake task lists" do
      expect(table.keys).to match_array(rake_answers[0])
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
    it "gives the rake task a directory's registry type, nil for none" do
      expect(rake_answers[1..2]).to eq(%w[git_graph] + [nil])
    end

    it "gives the registry the directories of a type" do
      expect(Sirena::DiagramRegistry.corpus_directories(:git_graph))
        .to eq(%w[git gitgraph])
    end

    it "reads one table: a seeded wrong entry changes both readers" do
      stub_const("#{described_class}::DIRECTORIES",
                 table.merge("gitgraph" => :pie).freeze)

      expect([rake_answers[3],
              Sirena::DiagramRegistry.corpus_directories(:git_graph)])
        .to eq(["pie", %w[git]])
    end
  end
end
