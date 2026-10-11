# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Renderer::C4 do
  subject(:renderer) { described_class.new }

  let(:source) { File.read("examples/c4/01-context-diagram.mmd") }
  let(:diagram) { Sirena::Parser::C4.new.parse(source) }
  let(:scene) { Sirena::Layout::C4.new.call(diagram) }

  it "uses the base document factory" do
    expect(described_class.instance_method(:create_document).owner)
      .to eq(Sirena::Renderer::Base)
  end

  it "copies the final Scene view box" do
    scene.view_box = "-5 -10 640 480"

    expect(renderer.render(scene).view_box).to eq(scene.view_box)
  end

  it "copies the final Scene overflow" do
    scene.overflow = "visible"

    expect(renderer.render(scene).overflow).to eq(scene.overflow)
  end

  it "preserves the registered default SVG bytes" do
    digest = Digest::SHA256.hexdigest(renderer.render(scene).to_xml)

    expect(digest)
      .to eq("81b4519c8101cdd6b5b75c361bff4ac6f8eb2c58d3d0a80519749eb0af38331c")
  end
end
