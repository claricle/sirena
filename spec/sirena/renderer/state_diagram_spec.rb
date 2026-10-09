# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::StateDiagram do
  let(:renderer) { described_class.new }
  let(:expected_hook_calls) do
    {
      calculate_width: 1,
      calculate_height: 1,
      create_state_shape: 2,
      create_normal_state: 2,
      calculate_transition_path: 1,
      create_path_with_bends: 1,
      create_transition_label: 1,
    }
  end
  let(:hook_renderer_class) do
    Class.new(described_class) do
      attr_reader :hook_calls

      def initialize(...)
        super
        @hook_calls = Hash.new(0)
      end

      protected

      def calculate_width(graph)
        @hook_calls[:calculate_width] += 1
        super
      end

      def calculate_height(graph)
        @hook_calls[:calculate_height] += 1
        super
      end

      def create_state_shape(state, state_type)
        @hook_calls[:create_state_shape] += 1
        super
      end

      def create_normal_state(x_position, y_position, width, height)
        @hook_calls[:create_normal_state] += 1
        super
      end

      def calculate_transition_path(source, target, transition)
        @hook_calls[:calculate_transition_path] += 1
        super
      end

      def create_path_with_bends(
        source_x, source_y, target_x, target_y, bend_points
      )
        @hook_calls[:create_path_with_bends] += 1
        super
      end

      def create_transition_label(source, target, label)
        @hook_calls[:create_transition_label] += 1
        super
      end
    end
  end

  def forbid_layout_geometry(method_name)
    allow(Sirena::Layout::StateDiagram).to receive(method_name)
      .and_raise("geometry recalculated")
  end

  describe "#render" do
    let(:graph) do
      {
        id: "state_diagram",
        children: [
          {
            id: "idle",
            x: 10,
            y: 10,
            width: 120,
            height: 60,
            labels: [{ text: "Idle", width: 40, height: 14 }],
            metadata: { state_type: "normal" },
          },
          {
            id: "active",
            x: 180,
            y: 10,
            width: 120,
            height: 60,
            labels: [{ text: "Active", width: 50, height: 14 }],
            metadata: { state_type: "normal" },
          },
        ],
        edges: [
          {
            id: "idle_to_active",
            sources: ["idle"],
            targets: ["active"],
            labels: [{ text: "start", width: 40, height: 14 }],
            sections: [{ bendPoints: [{ x: 155, y: 90 }] }],
            metadata: { trigger: "start" },
          },
        ],
      }
    end

    it "renders graph to SVG document" do
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "includes states in SVG" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)
      expect(groups.length).to be > 0
    end

    it "renders normal states as rounded rectangles" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
      expect(rects.first.rx).to eq(10)
    end

    it "renders start state as filled circle" do
      graph[:children][0][:metadata][:state_type] = "start"

      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      circles = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Circle) && c.fill == "#000000"
      end

      expect(circles).not_to be_empty
    end

    it "renders end state as double circle" do
      graph[:children][0][:metadata][:state_type] = "end"

      svg = renderer.render(graph)

      # Find all groups including nested ones
      all_circles = []
      svg.children.each do |child|
        next unless child.is_a?(Sirena::Svg::Group)

        child.children.each do |gc|
          if gc.is_a?(Sirena::Svg::Group)
            all_circles.concat(
              gc.children.grep(Sirena::Svg::Circle),
            )
          elsif gc.is_a?(Sirena::Svg::Circle)
            all_circles << gc
          end
        end
      end

      expect(all_circles.length).to be >= 2
    end

    it "renders choice state as diamond" do
      graph[:children][0][:metadata][:state_type] = "choice"

      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      polygons = groups.flat_map(&:children).grep(Sirena::Svg::Polygon)

      expect(polygons).not_to be_empty
    end

    it "renders fork state as thick bar" do
      graph[:children][0][:metadata][:state_type] = "fork"

      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect) && c.fill == "#000000"
      end

      expect(rects).not_to be_empty
    end

    it "renders state labels as text elements" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      # `content` is `collection: true`, so read it through Array(...).
      expect(texts.map { |t| Array(t.content).join }).to include("Idle")
    end

    it "keeps accumulated state text inside its rectangle" do
      diagram = Sirena::Parser::StateDiagram.new.parse(<<~MERMAID)
        stateDiagram-v2
        state "ALIAS_ONE" as A
        A : DESC_ONE
        state "ALIAS_TWO" as A
        A : DESC_TWO
      MERMAID
      rendered_graph = Sirena::Layout::StateDiagram.new
        .to_graph(diagram)
      svg = renderer.render(rendered_graph)
      state_group = svg.children.find { |child| child.id == "state-A" }
      rectangle = state_group.children.grep(Sirena::Svg::Rect).first
      texts = state_group.children.grep(Sirena::Svg::Text)
      labels = rendered_graph.children.first.labels

      expect(texts.length).to eq(labels.length)
      expect(texts.map { |t| Array(t.content).join }).to eq(labels.map(&:text))

      text_bounds = texts.zip(labels).map do |text, label|
        [text.y - (label.height / 2), text.y + (label.height / 2)]
      end
      expect(text_bounds.flatten.min).to be >= rectangle.y
      expect(text_bounds.flatten.max).to be <= rectangle.y + rectangle.height
    end

    it "renders transitions as paths" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      paths = groups.flat_map(&:children).grep(Sirena::Svg::Path)

      expect(paths).not_to be_empty
    end

    it "renders transition labels" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text) && Array(c.content).join == "start"
      end

      expect(texts).not_to be_empty
    end

    it "serializes a typed Scene without recalculating geometry" do
      scene = Sirena::Layout::StateDiagram.from_graph(graph)
      forbid_layout_geometry(:shape_geometry)
      forbid_layout_geometry(:transition_label_geometry)
      expect { renderer.render(scene) }.not_to raise_error
    end

    it "routes public rendering through every released geometry hook" do
      hook_renderer = hook_renderer_class.new

      hook_renderer.render(graph)

      expect(hook_renderer.hook_calls).to eq(expected_hook_calls)
    end

    it "emits the font sizes already resolved by the themed layout" do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      scene = Sirena::Layout::StateDiagram.from_graph(graph, theme: theme)
      svg = described_class.new(theme: theme).render(scene).to_xml

      expect(svg).to include('font-size="16"').and include('font-size="14"')
    end
  end
end
