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
      expect(render_graph(graph)).to be_a(Sirena::Svg::Document)
    end

    it "renders a document with positive width" do
      expect(render_graph(graph).width).to be > 0
    end

    it "renders a document with positive height" do
      expect(render_graph(graph).height).to be > 0
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
    end

    it "renders the first node label as its text" do
      svg = render_graph(graph)
      groups = svg.children.grep(Sirena::Svg::Group)
      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

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
    { "-->" => 1, "---" => 0, "-.->" => 1, "-.-" => 0,
      "==>" => 1, "===" => 0 }.each do |link, arrowheads|
      it "draws an arrowhead only for a link that has one: #{link}" do
        svg = Sirena.render("flowchart TD\n  A#{link}B\n")

        expect(svg.scan("<polygon").length).to eq(arrowheads)
      end
    end
  end

  describe "#render with no boxes to draw" do
    let(:empty_graph) { { id: "flowchart", children: [], edges: [] } }

    # mmdc draws the same source 16px square (its 8px padding either side)
    # at viewBox `-8 -8 16 16`; sirena's viewBox origin is always 0 0
    # (`Svg::Document#calculate_view_box`, for every diagram type).
    empty_dimensions = { width: 16.0, height: 16.0, view_box: "0 0 16.0 16.0" }
    empty_dimensions.each do |property, expected|
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

  describe "text size" do
    let(:source) { "flowchart TD\nsubgraph s [T]\nA -->|go| B\nend\n" }
    let(:sizes) do
      lambda do |theme|
        Sirena::Engine.new(theme: theme).render(source)
          .scan(/<text[^>]*font-size="([^"]*)"/).flatten.uniq
      end
    end

    it "draws nodes, titles and edge labels at mmdc's 16px" do
      expect(sizes.call({ typography: { font_size_small: 12.0,
                                        font_size_normal: 14.0 } }))
        .to eq(["16.0"])
    end

    it "draws them at the theme's flowchart_font_size" do
      expect(sizes.call({ typography: { flowchart_font_size: 20.0 } }))
        .to eq(["20.0"])
    end
  end

  # mmdc draws a `<br>` in a node label as a second line of the same text.
  describe "a node label of two lines" do
    let(:xml) { Sirena.render("flowchart TD\n  A[\"one<br>two\"]\n") }
    let(:group) { xml[%r{<g id="node-A".*?</g>}m] }
    let(:box) do
      group.match(/<rect[^>]*\sy="([\d.]+)"[^>]*height="([\d.]+)"/)
        .captures.map(&:to_f)
    end
    let(:baselines) do
      group.scan(/<tspan[^>]*\sy="([\d.]+)"/).flatten.map(&:to_f)
    end

    it "is one tspan for each line, the first holding its place with a space" do
      expect(group.scan(%r{<tspan[^>]*>([^<]*)</tspan>}).flatten)
        .to eq(["one ", "two"])
    end

    it "steps down one line" do
      first = group[/<text[^>]*\sy="([\d.]+)"/, 1].to_f

      expect(baselines.first - first).to be_within(0.01).of(24.0)
    end

    it "centres the pair on the node" do
      centre = box.first + (box.last / 2)
      first = group[/<text[^>]*\sy="([\d.]+)"/, 1].to_f

      expect(((first + baselines.first) / 2) - 5.6)
        .to be_within(0.01).of(centre)
    end
  end
end
