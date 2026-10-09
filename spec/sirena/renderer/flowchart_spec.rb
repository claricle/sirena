# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Flowchart do
  let(:renderer) { described_class.new }

  def render_graph(graph)
    scene = Sirena::Layout::Flowchart.from_graph(graph, theme: renderer.theme)
    renderer.render(scene)
  end

  describe "#render" do
    let(:graph) do
      {
        id: "flowchart",
        children: [
          {
            id: "A",
            x: 10,
            y: 10,
            width: 100,
            height: 50,
            labels: [{ text: "Start", width: 50, height: 14 }],
            metadata: { shape: "rect" },
          },
          {
            id: "B",
            x: 150,
            y: 10,
            width: 100,
            height: 50,
            labels: [{ text: "End", width: 35, height: 14 }],
            metadata: { shape: "rect" },
          },
        ],
        edges: [
          {
            id: "A_to_B",
            sources: ["A"],
            targets: ["B"],
            metadata: { arrow_type: "arrow" },
          },
        ],
      }
    end

    it "renders graph to SVG document" do
      svg = render_graph(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "includes nodes in SVG" do
      svg = render_graph(graph)

      # Should have groups for nodes
      groups = svg.children.grep(Sirena::Svg::Group)
      expect(groups.length).to be > 0
    end

    it "renders rectangle nodes" do
      svg = render_graph(graph)

      # Find groups and check for rect children
      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
    end

    it "renders circle nodes" do
      graph[:children][0][:metadata][:shape] = "circle"

      svg = render_graph(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      circles = groups.flat_map(&:children).grep(Sirena::Svg::Circle)

      expect(circles).not_to be_empty
    end

    it "renders node labels as text elements" do
      svg = render_graph(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      # `content` is `collection: true`, so read it through Array(...).
      expect(Array(texts.first.content).join).to eq("Start")
    end

    it "renders edges as paths" do
      svg = render_graph(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      paths = groups.flat_map(&:children).grep(Sirena::Svg::Path)

      expect(paths).not_to be_empty
    end

    # One spelling for each of the six types `canonical_arrow_type` can
    # build — `arrow` `line` `dotted_arrow` `dotted_line` `thick_arrow`
    # `thick_line`, in the order listed below — not a sample. The
    # renderer decides the head from a hard-coded whitelist
    # (`arrow_type?`) that lives apart from the generative rule, so the
    # two can drift silently: adding `thick_line` and `dotted_line` to
    # that list draws an arrowhead on `A===B` and `A-.-B` that mermaid
    # does not draw. Accepting those two headless spellings at all was
    # justified by this guarantee, so this is where it is pinned.
    #
    # Count the arrowhead we DRAW, not a `marker-end` attribute. That
    # attribute was a proxy and it pointed the wrong way: before link
    # heads existed this file emitted `marker-end="url(#arrowhead)"`
    # with no `<marker>` and no `<defs>` anywhere in the document, so
    # the assertion passed on all six rows while no arrowhead was
    # rendered at all. Measured against mmdc 11.12.0, the polygon count
    # below matches mermaid on every row.
    it "draws an arrowhead only for a link that has one" do
      { "-->" => 1, "---" => 0, "-.->" => 1, "-.-" => 0,
        "==>" => 1, "===" => 0 }.each do |link, arrowheads|
        source = "flowchart TD\n  A#{link}B\n"
        svg = Sirena.render(source)
        message = "source #{source.inspect}"

        expect(svg.scan("<polygon").length).to eq(arrowheads), message
      end
    end
  end

  describe "#render with no boxes to draw" do
    let(:empty_graph) { { id: "flowchart", children: [], edges: [] } }

    # `create_document`'s own padding (20 per side, `Renderer::Base#create_document`)
    # is the only number this canvas carries -- `calculate_width`/`calculate_height`
    # contribute nothing when there is nothing drawn, the same as they would for a
    # single zero-sized box. mmdc draws the same source at `-8 -8 16 16` (a
    # percentage width, not a fixed one, and its own 8px padding), which this does
    # not try to match byte-for-byte: sirena's viewBox origin never goes negative
    # (`Svg::Document#calculate_view_box` always emits `0 0 W H`, for every diagram
    # type), and its padding constant is sirena's own, not mermaid's.
    { width: 40.0, height: 40.0, view_box: "0 0 40 40" }.each do |property, expected|
      it "sets #{property} to #{expected.inspect}" do
        svg = render_graph(empty_graph)

        expect(svg.public_send(property)).to eq(expected)
      end
    end

    # Passes before and after this change (`render` never drew anything for
    # a graph with no children even at the old fixed 800x600) -- keep it: it
    # is the only check that a future addition to `render` does not draw
    # something into a canvas meant to stay blank.
    it "draws no child elements" do
      svg = render_graph(empty_graph)

      expect(svg.children).to be_empty
    end
  end
end
