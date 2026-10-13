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

  let(:result) { scene(body) }

  context "with repeated merge tags" do
    let(:body) do
      <<~MERMAID
        commit id: "root"
        branch feature
        commit id: "work"
        checkout main
        merge feature id: "release" tag: "one" tag: "two"
      MERMAID
    end

    it "preserves repeated merge tags in source order" do
      expect(labels(result, "tag")).to eq(%w[one two])
    end
  end

  context "with a cherry-pick" do
    let(:body) do
      <<~MERMAID
        commit id: "ZERO"
        branch develop
        commit id: "A"
        checkout main
        cherry-pick id: "A"
      MERMAID
    end

    it "gives a cherry-pick one generated label without repeating its id" do
      expect([labels(result, "id"), labels(result, "tag")])
        .to eq([%w[ZERO A], ["cherry-pick:A"]])
    end
  end

  context "with a cherry-pick of a merge commit" do
    let(:body) do
      <<~MERMAID
        commit id: "ZERO"
        branch feature
        commit id: "A"
        commit id: "B"
        checkout main
        merge feature id: "M"
        branch release
        cherry-pick id: "M" parent: "B"
      MERMAID
    end

    it "includes the selected parent in a generated cherry-pick label" do
      expect(labels(result, "tag"))
        .to eq(["cherry-pick:M|parent:B"])
    end
  end

  context "with a custom cherry-pick tag" do
    let(:body) do
      <<~MERMAID
        commit id: "ZERO"
        branch develop
        commit id: "A"
        checkout main
        cherry-pick id: "A" tag: "MyTag"
      MERMAID
    end

    it "keeps a custom cherry-pick tag once instead of generating one" do
      expect(labels(result, "tag")).to eq(["MyTag"])
    end
  end

  context "with an explicitly empty cherry-pick tag" do
    let(:body) do
      <<~MERMAID
        commit id: "ZERO"
        branch develop
        commit id: "A"
        checkout main
        cherry-pick id: "A" tag: ""
      MERMAID
    end

    it "treats an explicitly empty cherry-pick tag as no label" do
      expect(labels(result, "tag")).to eq([])
    end
  end

  context "with an initial branch declaration" do
    let(:body) do
      <<~MERMAID
        branch new
        commit
        commit
      MERMAID
    end

    it "keeps the empty root lane after an initial branch declaration" do
      expect(result.branches.map { |b| [b.name, b.label&.text] })
        .to eq([["main", "main"], ["new", "new"]])
    end
  end
end
