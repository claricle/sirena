# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart do
  let(:source) { File.read("spec/fixtures/flowchart/label_clearance.mmd") }

  def scene_for(text, font_size = 16)
    layout = described_class.new
    layout.theme = Sirena::Theme.new(
      typography: Sirena::Theme::Typography.new(flowchart_font_size: font_size),
    )
    layout.call(Sirena::Parser::Flowchart.new.parse(text))
  end

  def cluster_title_bounds(cluster)
    title = cluster.labels.first
    [title.y - (title.height / 2.0), title.y + (title.height / 2.0)]
  end

  def label_outside?(label, cluster)
    !horizontal_overlap?(label, cluster) || !vertical_overlap?(label, cluster)
  end

  def horizontal_overlap?(label, cluster)
    left = label.x - (label.width / 2.0)
    right = label.x + (label.width / 2.0)
    right >= cluster.shape_x && left <= cluster.shape_x + cluster.shape_width
  end

  def vertical_overlap?(label, cluster)
    top = label.y - label.height
    bottom = label.y + (label.font_size / 4.0)
    bottom >= cluster.shape_y && top <= cluster.shape_y + cluster.shape_height
  end

  def ordinary_geometry(scene)
    cluster = scene.children.find(&:cluster)
    arrow = scene.edges.find { |edge| edge.source == "B" && edge.target == "C" }
    [cluster.children.map { |node| [node.id, node.y] }, arrow.path]
  end

  def internal_label_evidence(scene)
    edge = scene.edges.first
    section = edge.sections.first
    midpoint = (section.start_point.y + section.end_point.y) / 2.0
    [edge.labels.first.y, midpoint - 5]
  end

  def cluster_for_direction(direction)
    scene_for(source.sub("flowchart TD", "flowchart #{direction}"))
      .children.find(&:cluster)
  end

  def crossing_label_evidence(direction)
    scene = scene_for(source.sub("flowchart TD", "flowchart #{direction}"))
    cluster = scene.children.find(&:cluster)
    labels = scene.edges.flat_map(&:labels)
    [labels.map(&:text), labels.all? { |label| label_outside?(label, cluster) }]
  end

  def empty_cluster_graph
    { id: "scene", edges: [], children: [
      { id: "empty", x: 8, y: 8, width: 100, height: 50, children: [],
        labels: [{ text: "Empty", width: 40, height: 16 }],
        metadata: { cluster: true } },
    ] }
  end

  %w[TD BT LR RL].each do |direction|
    it "keeps the title clear of child nodes in #{direction} flow" do
      cluster = cluster_for_direction(direction)
      top, bottom = cluster_title_bounds(cluster)

      expect([top, bottom]).to match(
        [be > cluster.shape_y, be < cluster.children.map(&:y).min],
      )
    end

    it "clears the cluster with crossing labels in #{direction} flow" do
      expect(crossing_label_evidence(direction))
        .to match([contain_exactly("Mermaid", "PlantUML"), true])
    end
  end

  it "reserves enough title space when a theme enlarges flowchart text" do
    cluster = scene_for(source, 40).children.find(&:cluster)
    top, bottom = cluster_title_bounds(cluster)

    expect([top, bottom]).to match(
      [be > cluster.shape_y, be < cluster.children.map(&:y).min],
    )
  end

  it "preserves the ordinary arrow endpoints and node positions" do
    expect(ordinary_geometry(scene_for(source)))
      .to eq([[["A", 33.0], ["B", 137.0]],
              "M 181.3 277.1 L 111.1 406.1"])
  end

  it "retains the midpoint label on an edge wholly inside a subgraph" do
    text = "flowchart TD\n subgraph s\n a -->|inside| b\n end\n"
    actual, expected = internal_label_evidence(scene_for(text))

    expect(actual).to eq(expected)
  end

  it "retains empty cluster titles in the public hand-positioned adapter" do
    scene = described_class.from_graph(empty_cluster_graph)

    expect(scene.children.first.labels.first.y).to eq(28)
  end

  it "omits an empty subgraph while retaining unrelated nodes" do
    scene = scene_for("flowchart TD\n x\n subgraph empty\n end\n")

    expect(scene.children.map(&:id)).to eq(["x"])
  end
end
