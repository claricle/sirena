# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe Sirena::Renderer::ErDiagram do
  let(:source) do
    <<~MERMAID
      erDiagram
        CUSTOMER {
          int id PK
        }
        ORDER {
          int id PK
        }
        CUSTOMER ||--o{ ORDER : places
    MERMAID
  end
  let(:dark_paints) do
    [["#2d2d30", "#858585", "#858585", "#d4d4d4", "#d4d4d4"],
     ["#858585", "#d4d4d4"]]
  end
  let(:explicit_paints) do
    ["#123456", "#abcdef", "#abcdef", "#fedcba", "#fedcba"]
  end

  def document(theme, input = source)
    xml = Sirena::Engine.new(theme: theme).render(input)
    REXML::Document.new(xml)
  end

  def entity_paints(document)
    entity = REXML::XPath.first(document, "//*[@id='entity-CUSTOMER']")
    rect = REXML::XPath.first(entity, "rect")
    separator = REXML::XPath.first(entity, "line")
    texts = REXML::XPath.match(entity, "text")
    [rect.attributes["fill"], rect.attributes["stroke"],
     separator.attributes["stroke"],
     *texts.map { |text| text.attributes["fill"] }]
  end

  def relationship_paints(document)
    relationship = REXML::XPath.first(
      document, "//*[@id='rel-CUSTOMER_to_ORDER']"
    )
    shapes = REXML::XPath.match(relationship, "path|line|circle")
    texts = REXML::XPath.match(relationship, "text")
    [*shapes.map { |shape| shape.attributes["stroke"] },
     *texts.map { |text| text.attributes["fill"] }]
  end

  def all_paints(theme)
    result = document(theme)
    [entity_paints(result), relationship_paints(result).uniq]
  end

  def override_source
    "#{source.sub('CUSTOMER {', 'CUSTOMER:::custom {')}" \
      "classDef custom fill:#123456,stroke:#abcdef,color:#fedcba\n"
  end

  it "preserves the exact default SVG" do
    xml = Sirena::Engine.new.render(source)

    expect(Digest::SHA256.hexdigest(xml))
      .to eq("1a6e4403d58174761c78f454f981d655ef32d5e02c6dd0f998dced2b24439d41")
  end

  it "uses dark theme roles for entities and relationships" do
    expect(all_paints(:dark)).to eq(dark_paints)
  end

  it "leaves unset scalar roles unpainted" do
    theme = Sirena::Theme.new(colors: {})

    expect(all_paints(theme).flatten).to all(be_nil)
  end

  it "keeps explicit classDef paint above theme roles" do
    result = document(:dark, override_source)

    expect(entity_paints(result)).to eq(explicit_paints)
  end
end
