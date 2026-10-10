# frozen_string_literal: true

require "spec_helper"
require_relative "../../tasks/support/spec_shard"

module SpecShardSpecHelpers
  def groups(count)
    (1..count).map { |index| Sirena::SpecShard.new(index, count).files }
  end

  def weight_of(group)
    weights = Sirena::SpecShard::WEIGHTS
    group.sum { |file| weights.fetch(file, Sirena::SpecShard::DEFAULT_WEIGHT) }
  end
end

RSpec.describe Sirena::SpecShard do
  include SpecShardSpecHelpers

  let(:all_files) { Dir.glob(described_class::PATTERN).uniq.sort }
  let(:heavy) do
    %w[spec/sirena/lint_debt_spec.rb spec/sirena/lint_debt_scoreboard_spec.rb]
  end

  describe "#files" do
    [1, 2, 3, 5].each do |count|
      it "runs every spec file exactly once across #{count} groups" do
        expect(groups(count).flatten.sort).to eq(all_files)
      end
    end

    it "keeps the two slowest files in different groups" do
      sizes = groups(2).map { |group| (group & heavy).size }

      expect(sizes).to eq([1, 1])
    end

    it "balances the weighted load of three groups within 30 seconds" do
      loads = groups(3).map { |group| weight_of(group) }
      loads[-1] += described_class::TAIL_SECONDS

      expect(loads.max - loads.min).to be < 30
    end

    it "still runs a file the weight table does not know" do
      shards = [1, 2].map { |i| described_class.new(i, 2) }
      dealt = shards.flat_map { |shard| shard.files(%w[spec/new_spec.rb]) }

      expect(dealt).to eq(%w[spec/new_spec.rb])
    end

    it "runs a file listed twice once" do
      shard = described_class.new(1, 1)

      expect(shard.files(%w[spec/a_spec.rb spec/a_spec.rb])).to eq(
        %w[spec/a_spec.rb],
      )
    end
  end

  describe "the weight table" do
    it "names only files that exist" do
      expect(described_class::WEIGHTS.keys - all_files).to eq([])
    end
  end

  describe ".from_env" do
    it "is nil when the variable is unset" do
      expect(described_class.from_env({})).to be_nil
    end

    it "is nil when the variable is empty" do
      expect(described_class.from_env("SIRENA_SPEC_SHARD" => " ")).to be_nil
    end

    it "reads index and count" do
      shard = described_class.from_env("SIRENA_SPEC_SHARD" => "2/3")

      expect([shard.index, shard.count]).to eq([2, 3])
    end

    ["0/3", "4/3", "1/0", "x/3", "2"].each do |bad|
      it "refuses #{bad.inspect}" do
        expect { described_class.from_env("SIRENA_SPEC_SHARD" => bad) }
          .to raise_error(ArgumentError)
      end
    end
  end

  describe "#runs_tail?" do
    it "is true for the last group only" do
      flags = (1..3).map { |i| described_class.new(i, 3).runs_tail? }

      expect(flags).to eq([false, false, true])
    end
  end
end
