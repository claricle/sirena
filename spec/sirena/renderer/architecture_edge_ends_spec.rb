# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Architecture do
  # The diagram model keeps no arrow flag, and mmdc draws none for "--".
  it "draws an edge as a bare line with no arrowhead" do
    diagram = Sirena::Parser::Architecture.new.parse(<<~MMD)
      architecture-beta
          service a(server)[A]
          service b(server)[B]
          a:R -- L:b
    MMD
    scene = Sirena::Layout::Architecture.new.call(diagram)
    xml = described_class.new.render(scene).to_xml

    expect([xml.include?("<polygon"), xml.include?("marker-end")])
      .to eq([false, false])
  end
end
