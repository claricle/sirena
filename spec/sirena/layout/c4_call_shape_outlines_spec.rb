# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4, "#call shape outlines" do
  let(:scene) do
    source = <<~MERMAID
      C4Context
      SystemDb(db, "Store")
      SystemQueue(q, "Bus")
      System(plain, "Plain")
    MERMAID
    described_class.new.call(Sirena::Parser::C4.new.parse(source))
  end
  let(:svg) { Sirena::Renderer::C4.new.render(scene).to_xml }

  def node(id)
    scene.children.find { |child| child.id == id }
  end

  it "gives a database node the cylinder body" do
    db = node("db")

    expect(db.outline)
      .to start_with("M#{db.x},#{db.y}c0,-10 #{db.width / 2},-10")
  end

  it "gives a database node the cylinder rim" do
    db = node("db")
    half = db.width / 2

    expect(db.rim).to eq("M#{db.x},#{db.y}c0,10 #{half},10 #{half},10" \
                         "c0,0 #{half},0 #{half},-10")
  end

  it "gives a queue node the pill body" do
    q = node("q")
    half = q.height / 2

    expect(q.outline).to include("l#{q.width},0c5,0 5,#{half} 5,#{half}")
  end

  it "gives a queue node the pill rim" do
    q = node("q")

    expect(q.rim).to start_with("M#{q.x + q.width},#{q.y}c-5,0")
  end

  it "leaves a plain system without outline paths" do
    expect([node("plain").outline, node("plain").rim]).to eq([nil, nil])
  end

  it "serializes the scene's outline unchanged" do
    expect(svg).to include(%(d="#{node('db').outline}"))
  end

  it "serializes the scene's rim unchanged" do
    expect(svg).to include(%(d="#{node('db').rim}"))
  end
end
