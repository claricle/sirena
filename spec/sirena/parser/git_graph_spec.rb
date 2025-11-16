# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"

RSpec.describe Sirena::Parser::GitGraphParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple commits" do
      it "parses a single commit" do
        source = <<~MERMAID
          gitGraph
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::GitGraph)
        expect(diagram.commits.size).to eq(1)
        expect(diagram.commits.first.branch_name).to eq("main")
      end

      it "parses multiple commits with IDs" do
        source = <<~MERMAID
          gitGraph
            commit id: "One"
            commit id: "Two"
            commit id: "Three"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.size).to eq(3)
        expect(diagram.commits.map(&:id)).to eq(["One", "Two", "Three"])
      end

      it "parses commits with types" do
        source = <<~MERMAID
          gitGraph
            commit type: NORMAL
            commit type: REVERSE
            commit type: HIGHLIGHT
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.size).to eq(3)
        expect(diagram.commits.map(&:type)).to eq(
          ["NORMAL", "REVERSE", "HIGHLIGHT"]
        )
      end

      it "parses commits with tags" do
        source = <<~MERMAID
          gitGraph
            commit tag: "v1.0"
            commit id: "Two" tag: "v2.0"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.size).to eq(2)
        expect(diagram.commits.map(&:tag)).to eq(["v1.0", "v2.0"])
      end
    end

    context "with branches" do
      it "parses branch creation" do
        source = <<~MERMAID
          gitGraph
            commit
            branch develop
            checkout develop
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.branches.size).to eq(2) # main and develop
        expect(diagram.branches.map(&:name)).to include("develop")
        expect(diagram.commits.size).to eq(2)
        expect(diagram.commits.last.branch_name).to eq("develop")
      end

      it "parses branch with order" do
        source = <<~MERMAID
          gitGraph
            commit
            branch test1 order: 3
            branch test2 order: 2
        MERMAID

        diagram = parser.parse(source)
        branch1 = diagram.branches.find { |b| b.name == "test1" }
        branch2 = diagram.branches.find { |b| b.name == "test2" }
        expect(branch1.order).to eq(3)
        expect(branch2.order).to eq(2)
      end

      it "parses switch statement" do
        source = <<~MERMAID
          gitGraph
            commit
            branch testBranch
            switch testBranch
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.last.branch_name).to eq("testBranch")
      end
    end

    context "with merges" do
      it "parses merge operations" do
        source = <<~MERMAID
          gitGraph
            commit
            branch develop
            checkout develop
            commit id: "Feature"
            checkout main
            merge develop
        MERMAID

        diagram = parser.parse(source)
        merge_commit = diagram.commits.last
        expect(merge_commit.is_merge).to be true
        expect(merge_commit.merge_branch).to eq("develop")
      end

      it "parses merge with id and tag" do
        source = <<~MERMAID
          gitGraph
            commit
            branch develop
            checkout develop
            commit
            checkout main
            merge develop id: "M1" tag: "v1.0"
        MERMAID

        diagram = parser.parse(source)
        merge_commit = diagram.commits.last
        expect(merge_commit.id).to eq("M1")
        expect(merge_commit.tag).to eq("v1.0")
        expect(merge_commit.is_merge).to be true
      end
    end

    context "with cherry-picks" do
      it "parses cherry-pick operations" do
        source = <<~MERMAID
          gitGraph
            commit id: "A"
            branch feature
            checkout feature
            commit id: "B"
            checkout main
            cherry-pick id: "B"
        MERMAID

        diagram = parser.parse(source)
        cp_commit = diagram.commits.last
        expect(cp_commit.is_cherry_pick).to be true
      end

      it "parses cherry-pick with parent and tag" do
        source = <<~MERMAID
          gitGraph
            commit id: "ZERO"
            branch feature
            checkout feature
            commit id: "A"
            checkout main
            cherry-pick id: "A" parent: "ZERO" tag: "v1.0"
        MERMAID

        diagram = parser.parse(source)
        cp_commit = diagram.commits.last
        expect(cp_commit.is_cherry_pick).to be true
        expect(cp_commit.cherry_pick_parent).to eq("ZERO")
        expect(cp_commit.tag).to eq("v1.0")
      end
    end

    context "with orientation" do
      it "parses TB orientation" do
        source = <<~MERMAID
          gitGraph TB:
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::GitGraph)
        expect(diagram.commits.size).to eq(1)
      end

      it "parses LR orientation" do
        source = <<~MERMAID
          gitGraph LR:
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::GitGraph)
        expect(diagram.commits.size).to eq(1)
      end
    end
  end
end