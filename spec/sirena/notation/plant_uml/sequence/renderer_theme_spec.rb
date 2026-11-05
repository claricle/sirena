# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/xpath"
require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Renderer do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:source) do
    <<~PLANTUML
      @startuml
      A -> B : hi
      note right : a note
      @enduml
    PLANTUML
  end
  let(:paint_attributes) do
    {
      note_fill: ["//*[starts-with(@id, 'note-')]/path", "fill"],
      node_fill: ["//*[@id='participant-A-20.0']/rect", "fill"],
      node_stroke: ["//*[@id='participant-A-20.0']/rect", "stroke"],
      edge_stroke: ["//*[@id='message-1']/path", "stroke"],
      label_text: ["//*[@id='message-1']/text", "fill"],
    }
  end

  def paint_roles(theme)
    svg = Sirena.render(source, notation: :plantuml, theme: theme)
    document = REXML::Document.new(svg)

    paint_attributes.to_h do |role, (xpath, attribute)|
      element = REXML::XPath.first(document, xpath)
      [role, element.attributes[attribute]]
    end
  end

  def expected_paint_roles(theme)
    paint_attributes.keys.to_h do |role|
      [role, theme.colors.public_send(role)]
    end
  end

  it "preserves the default SVG bytes" do
    svg = Sirena.render(source, notation: :plantuml)

    expect(Digest::SHA256.hexdigest(svg))
      .to eq("3aec4baa49f214f2635ad96aeb7df35f2de59500fa895fa309f8e9c90061a0ea")
  end

  it "uses every built-in theme's sequence paint roles" do
    %i[light dark high_contrast].each do |name|
      theme = Sirena::Theme::Registry.get(name)

      expect(paint_roles(theme)).to eq(expected_paint_roles(theme))
    end
  end

  it "paints the default theme with the PlantUML skin" do
    expect(paint_roles(Sirena::Theme::Registry.get(:default)))
      .to eq(note_fill: "#FEFFDD", node_fill: "#E2E2F0",
             node_stroke: "#181818", edge_stroke: "#181818",
             label_text: "#000000")
  end

  it "leaves omitted scalar paint roles unpainted" do
    theme = Sirena::Theme::Registry.get(:light).dup
    theme.colors = Sirena::Theme::ColorPalette.new

    expect(paint_roles(theme).values).to eq([nil, nil, nil, nil, nil])
  end
end
