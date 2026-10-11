# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  subject(:layout) { described_class.new }

  it "places a lone empty group at the grid origin when nothing else is drawn" do
    diagram = Sirena::Parser::Architecture.new
      .parse("architecture-beta\n  group g(cloud)[G]\n")
    group = layout.call(diagram).children.find { |node| node.id == "g" }

    expect([group.x, group.y]).to eq([60.0, 60.0])
  end
end
