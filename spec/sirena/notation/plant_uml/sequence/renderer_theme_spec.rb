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
      .to eq("26704b2d8430aef533b123ddd820b4086288ecd9d89e6fdef123d3e21960155a")
  end

  it "uses every built-in theme's sequence paint roles" do
    %i[default light dark high_contrast].each do |name|
      theme = Sirena::Theme::Registry.get(name)

      expect(paint_roles(theme)).to eq(expected_paint_roles(theme))
    end
  end

  it "leaves omitted scalar paint roles unpainted" do
    theme = Sirena::Theme::Registry.get(:default).dup
    theme.colors = Sirena::Theme::ColorPalette.new

    expect(paint_roles(theme).values).to eq([nil, nil, nil, nil, nil])
  end
end
