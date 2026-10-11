# frozen_string_literal: true

require "spec_helper"

module ErDiagramThemeSpecHelpers
  SOURCE = <<~MERMAID
    erDiagram
      CUSTOMER {
        int id PK
      }
      ORDER {
        int id PK
      }
      CUSTOMER ||--o{ ORDER : places
  MERMAID

  OVERRIDE_SOURCE = <<~MERMAID
    erDiagram
      CUSTOMER:::custom {
        int id PK
      }
      ORDER {
        int id PK
      }
      CUSTOMER ||--o{ ORDER : places
      classDef custom fill:#123456,stroke:#abcdef,color:#fedcba
  MERMAID

  module_function

  def document(theme, source = SOURCE)
    xml = Sirena::Engine.new(theme: theme).render(source)
    REXML::Document.new(xml)
  end

  def generic_paints(theme)
    doc = document(theme)
    entity = REXML::XPath.first(doc, "//*[@id='entity-CUSTOMER']")
    relationship = REXML::XPath.first(doc, "//*[@id='rel-CUSTOMER_to_ORDER']")
    [rect_paints(entity), separator_stroke(entity), text_fills(entity),
     shape_strokes(relationship), text_fills(relationship)]
  end

  def rect_paints(group)
    rect = REXML::XPath.first(group, "rect")
    [rect.attributes["fill"], rect.attributes["stroke"]]
  end

  def separator_stroke(group)
    REXML::XPath.first(group, "line").attributes["stroke"]
  end

  def text_fills(group)
    REXML::XPath.match(group, "text").map do |text|
      text.attributes["fill"]
    end.uniq
  end

  def shape_strokes(group)
    REXML::XPath.match(group, "*").filter_map do |shape|
      shape.attributes["stroke"]
    end.uniq
  end

  def explicit_paints
    doc = document(:dark, OVERRIDE_SOURCE)
    entity = REXML::XPath.first(doc, "//*[@id='entity-CUSTOMER']")
    [rect_paints(entity), separator_stroke(entity), text_fills(entity)]
  end
end

RSpec.describe Sirena::Renderer::ErDiagram do
  {
    default: [%w[#ffffff #000000], "#000000", ["#000000"],
              ["#000000"], ["#000000"]],
    dark: [%w[#2d2d30 #858585], "#858585", ["#d4d4d4"],
           ["#858585"], ["#d4d4d4"]],
    high_contrast: [%w[#000000 #ffffff], "#ffffff", ["#ffffff"],
                    ["#ffffff"], ["#ffffff"]],
  }.each do |theme, expected|
    it "uses every generic #{theme} theme role" do
      expect(ErDiagramThemeSpecHelpers.generic_paints(theme)).to eq(expected)
    end
  end

  it "keeps explicit classDef paint above the dark theme" do
    expect(ErDiagramThemeSpecHelpers.explicit_paints).to eq(
      [%w[#123456 #abcdef], "#abcdef", ["#fedcba"]],
    )
  end
end
