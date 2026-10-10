# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Architecture, "#render" do
  let(:source) do
    "architecture-beta\n group api(cloud)[API]\n " \
      "service db(database)[DB] in api\n"
  end
  let(:scene) do
    diagram = Sirena::Parser::Architecture.new.parse(source)
    Sirena::Layout::Architecture.new.call(diagram)
  end
  let(:group) { scene.children.find { |node| node.kind == "group" } }

  it "labels a group that has a label" do
    expect(described_class.new.render(scene).to_xml).to include(">API<")
  end

  it "renders a group without labels and without its title text" do
    group.labels = []

    expect(described_class.new.render(scene).to_xml).not_to include(">API<")
  end
end
