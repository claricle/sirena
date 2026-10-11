# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph do
  def scene(body)
    diagram = Sirena::Parser::GitGraph.new.parse("gitGraph\n#{body}")
    described_class.new.call(diagram)
  end

  def labels(result, kind)
    result.commits.flat_map(&:labels)
      .select { |label| label.kind == kind }
      .map(&:text)
  end

  it "preserves repeated merge tags in source order" do
    result = scene(<<~MERMAID)
      commit id: "root"
      branch feature
      commit id: "work"
      checkout main
      merge feature id: "release" tag: "one" tag: "two"
    MERMAID

    expect(labels(result, "tag")).to eq(%w[one two])
  end

  it "gives a cherry-pick one generated label without repeating its id" do
    result = scene(<<~MERMAID)
      commit id: "ZERO"
      branch develop
      commit id: "A"
      checkout main
      cherry-pick id: "A"
    MERMAID

    expect([labels(result, "id"), labels(result, "tag")])
      .to eq([%w[ZERO A], ["cherry-pick:A"]])
  end

  it "includes the selected parent in a generated cherry-pick label" do
    result = scene(<<~MERMAID)
      commit id: "ZERO"
      branch feature
      commit id: "A"
      commit id: "B"
      checkout main
      merge feature id: "M"
      branch release
      cherry-pick id: "M" parent: "B"
    MERMAID

    expect(labels(result, "tag"))
      .to eq(["cherry-pick:M|parent:B"])
  end

  it "keeps a custom cherry-pick tag once instead of generating one" do
    result = scene(<<~MERMAID)
      commit id: "ZERO"
      branch develop
      commit id: "A"
      checkout main
      cherry-pick id: "A" tag: "MyTag"
    MERMAID

    expect(labels(result, "tag")).to eq(["MyTag"])
  end

  it "treats an explicitly empty cherry-pick tag as no label" do
    result = scene(<<~MERMAID)
      commit id: "ZERO"
      branch develop
      commit id: "A"
      checkout main
      cherry-pick id: "A" tag: ""
    MERMAID

    expect(labels(result, "tag")).to eq([])
  end

  it "keeps the empty root lane after an initial branch declaration" do
    result = scene(<<~MERMAID)
      branch new
      commit
      commit
    MERMAID

    expect(result.branches.map { |branch| [branch.name, branch.label&.text] })
      .to eq([["main", "main"], ["new", "new"]])
  end
end
