# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::GitGraph do
  subject(:graph) { described_class.new.apply({ statements: statements }) }

  let(:statements) do
    [
      { commit: { options: [{ id: "c1" }, { message: "m" },
                            { type: "HIGHLIGHT" }, { tag: "v1" }, "junk"] } },
      { branch: { name: "dev", options: [{ order: "2" }] } },
      { branch: { name: "b2", options: [{ order: "3" }, "x"] } },
      { branch: { name: "b3", options: nil } },
      { checkout: { branch: "dev" } },
      { commit: {} },
      { switch: { branch: "main" } },
      { merge: { branch: "dev",
                 options: [{ id: "mm", tag: "t", type: "REVERSE" }] } },
      { cherry_pick: { options: [{ id: "c1", parent: "p" }] } },
      { acc_title: "  T  " },
      { acc_descr: " D1 \n  D2 " },
      "junk",
    ]
  end

  let(:expected_branches) do
    [
      { name: "main", order: 0,
        parent_branch: nil, created_at_commit: nil },
      { name: "dev", order: 2,
        parent_branch: "main", created_at_commit: "c1" },
      { name: "b2", order: 3,
        parent_branch: "main", created_at_commit: "c1" },
      { name: "b3", order: nil,
        parent_branch: "main", created_at_commit: "c1" },
    ]
  end

  let(:commit_fields) do
    graph[:commits].map do |c|
      c.values_at(:id, :type, :tag, :branch_name, :is_merge, :is_cherry_pick)
    end
  end

  let(:expected_commit_fields) do
    [
      ["c1", "HIGHLIGHT", "v1", "main", false, false],
      ["commit-2", "NORMAL", nil, "dev", false, false],
      ["mm", "REVERSE", "t", "main", true, false],
      ["c1", "NORMAL", nil, "main", false, true],
    ]
  end

  it "records branch orders from options and absent options" do
    expect(graph[:branches]).to eq(expected_branches)
  end

  it "builds commits with options, defaults, merges and cherry-picks",
     :aggregate_failures do
    expect(commit_fields).to eq(expected_commit_fields)
    expect(graph[:commits].last[:cherry_pick_parent]).to eq("p")
  end

  it "trims directive text line by line" do
    expect([graph[:acc_title], graph[:acc_description]]).to eq(%W[T D1\nD2])
  end

  it "treats a non-hash body or no options as an optionless commit" do
    statements = [{ commit: "x" }, { commit: { options: nil } }]
    result = described_class.new.apply({ statements: statements })
    pairs = result[:commits].map { |c| [c[:id], c[:type]] }
    expect(pairs).to eq([%w[commit-1 NORMAL], %w[commit-2 NORMAL]])
  end

  it "yields no commits for no statements" do
    expect(described_class.new.apply({ statements: [] })[:commits]).to eq([])
  end
end
