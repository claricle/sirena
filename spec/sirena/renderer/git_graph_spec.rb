# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/git_graph"
require "sirena/transform/git_graph"
require "sirena/diagram/git_graph"

RSpec.describe Sirena::Renderer::GitGraph do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe "#render" do
    context "with a simple linear git graph" do
      let(:layout) do
        {
          commits: [
            {
              id: "commit1",
              x: 80,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: nil,
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            },
            {
              id: "commit2",
              x: 160,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: nil,
              parent_ids: ["commit1"],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            }
          ],
          branches: [
            { name: "main", lane: 0, color: "#2563eb" }
          ],
          connections: [
            {
              from: "commit1",
              to: "commit2",
              from_x: 80,
              from_y: 60,
              to_x: 160,
              to_y: 60,
              from_branch: "main",
              to_branch: "main",
              type: :normal
            }
          ],
          width: 240,
          height: 120
        }
      end

      it "renders an SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it "includes commit circles" do
        svg = renderer.render(layout)
        circles = svg.children.select { |e| e.is_a?(Sirena::Svg::Circle) }
        expect(circles.length).to eq(2)
      end

      it "includes connection lines" do
        svg = renderer.render(layout)
        lines = svg.children.select { |e| e.is_a?(Sirena::Svg::Line) }
        expect(lines.length).to be >= 1
      end

      it "includes branch labels" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        expect(texts.length).to be >= 1
      end

      it "sets proper document dimensions" do
        svg = renderer.render(layout)
        expect(svg.width).to be > layout[:width]
        expect(svg.height).to be > layout[:height]
      end
    end

    context "with branches" do
      let(:layout) do
        {
          commits: [
            {
              id: "c1",
              x: 80,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: nil,
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            },
            {
              id: "c2",
              x: 160,
              y: 120,
              branch: "develop",
              lane: 1,
              type: "NORMAL",
              tag: nil,
              parent_ids: ["c1"],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            }
          ],
          branches: [
            { name: "main", lane: 0, color: "#2563eb" },
            { name: "develop", lane: 1, color: "#7c3aed" }
          ],
          connections: [
            {
              from: "c1",
              to: "c2",
              from_x: 80,
              from_y: 60,
              to_x: 160,
              to_y: 120,
              from_branch: "main",
              to_branch: "develop",
              type: :normal
            }
          ],
          width: 240,
          height: 180
        }
      end

      it "renders multiple branches" do
        svg = renderer.render(layout)
        circles = svg.children.select { |e| e.is_a?(Sirena::Svg::Circle) }
        expect(circles.length).to eq(2)
      end

      it "renders branch labels for all branches" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        text_contents = texts.map(&:content).compact
        expect(text_contents).to include("main")
        expect(text_contents).to include("develop")
      end
    end

    context "with merge commits" do
      let(:layout) do
        {
          commits: [
            {
              id: "c1",
              x: 80,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: nil,
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            },
            {
              id: "c2",
              x: 160,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: nil,
              parent_ids: ["c1"],
              is_merge: true,
              merge_branch: "develop",
              is_cherry_pick: false,
              cherry_pick_parent: nil
            }
          ],
          branches: [
            { name: "main", lane: 0, color: "#2563eb" }
          ],
          connections: [
            {
              from: "c1",
              to: "c2",
              from_x: 80,
              from_y: 60,
              to_x: 160,
              to_y: 60,
              from_branch: "main",
              to_branch: "main",
              type: :merge
            }
          ],
          width: 240,
          height: 120
        }
      end

      it "renders merge connections with dashed lines" do
        svg = renderer.render(layout)
        paths = svg.children.select { |e| e.is_a?(Sirena::Svg::Path) }
        expect(paths.length).to be >= 1
        expect(paths.first.stroke_dasharray).to eq("5,3")
      end
    end

    context "with commit tags" do
      let(:layout) do
        {
          commits: [
            {
              id: "c1",
              x: 80,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: "v1.0.0",
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            }
          ],
          branches: [
            { name: "main", lane: 0, color: "#2563eb" }
          ],
          connections: [],
          width: 160,
          height: 120
        }
      end

      it "renders tag labels" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        text_contents = texts.map(&:content).compact
        expect(text_contents).to include("v1.0.0")
      end
    end

    context "with commit types" do
      let(:layout) do
        {
          commits: [
            {
              id: "c1",
              x: 80,
              y: 60,
              branch: "main",
              lane: 0,
              type: "HIGHLIGHT",
              tag: nil,
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            },
            {
              id: "c2",
              x: 160,
              y: 60,
              branch: "main",
              lane: 0,
              type: "REVERSE",
              tag: nil,
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            }
          ],
          branches: [
            { name: "main", lane: 0, color: "#2563eb" }
          ],
          connections: [],
          width: 240,
          height: 120
        }
      end

      it "applies different colors for commit types" do
        svg = renderer.render(layout)
        circles = svg.children.select { |e| e.is_a?(Sirena::Svg::Circle) }
        expect(circles.length).to eq(2)
        # HIGHLIGHT and REVERSE should have different fills
        fills = circles.map(&:fill).uniq
        expect(fills.length).to be >= 2
      end
    end

    context "with cherry-pick commits" do
      let(:layout) do
        {
          commits: [
            {
              id: "c1",
              x: 80,
              y: 60,
              branch: "main",
              lane: 0,
              type: "NORMAL",
              tag: nil,
              parent_ids: [],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: false,
              cherry_pick_parent: nil
            },
            {
              id: "c2",
              x: 160,
              y: 120,
              branch: "develop",
              lane: 1,
              type: "NORMAL",
              tag: nil,
              parent_ids: ["c1"],
              is_merge: false,
              merge_branch: nil,
              is_cherry_pick: true,
              cherry_pick_parent: "c1"
            }
          ],
          branches: [
            { name: "main", lane: 0, color: "#2563eb" },
            { name: "develop", lane: 1, color: "#7c3aed" }
          ],
          connections: [
            {
              from: "c1",
              to: "c2",
              from_x: 80,
              from_y: 60,
              to_x: 160,
              to_y: 120,
              from_branch: "main",
              to_branch: "develop",
              type: :cherry_pick
            }
          ],
          width: 240,
          height: 180
        }
      end

      it "renders cherry-pick connections with dotted lines" do
        svg = renderer.render(layout)
        paths = svg.children.select { |e| e.is_a?(Sirena::Svg::Path) }
        expect(paths.length).to be >= 1
        expect(paths.first.stroke_dasharray).to eq("2,4")
      end
    end
  end
end