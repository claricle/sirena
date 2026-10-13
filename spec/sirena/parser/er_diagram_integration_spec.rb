# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module ErIntegrationSpecHelpers
  def entity_element(doc, name)
    doc.get_elements("//*[@id='entity-#{name}']").first
  end
end

RSpec.describe Sirena::Parser::ErDiagram, :aggregate_failures do
  include ErIntegrationSpecHelpers

  describe "complete ER diagram pipeline" do
    let(:diagram) { described_class.new.parse(source) }
    let(:scene) { Sirena::Layout::ErDiagram.new.to_graph(diagram) }
    let(:svg) { Sirena::Renderer::ErDiagram.new.render(scene) }

    context "with a simple ER diagram" do
      let(:source) { "erDiagram\nCUSTOMER ||--o{ ORDER" }
      let(:scene) { Sirena::Layout::ErDiagram.new.call(diagram) }

      it "parses a valid ErDiagram" do
        expect(diagram).to be_a(Sirena::Diagram::ErDiagram)
        expect(diagram.valid?).to be true
      end

      it "transforms to a Scene with both entities and the edge" do
        expect(scene).to be_a(Sirena::Layout::ErDiagram::Scene)
        expect(scene.children.length).to eq(2)
        expect(scene.edges.length).to eq(1)
      end

      it "renders a non-empty SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
        expect(svg.children).not_to be_empty
      end
    end

    context "with entity definitions holding attributes" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CUSTOMER {
            int id PK
            string name
            string email
          }
          ORDER {
            int order_id PK
            int customer_id FK
            date order_date
          }
          CUSTOMER ||--o{ ORDER
        MERMAID
      end

      it "parses the CUSTOMER attributes and its primary key" do
        customer = diagram.find_entity("CUSTOMER")

        expect(customer).not_to be_nil
        expect(customer.attributes.length).to eq(3)
        expect(customer.attributes.first.primary_key?).to be true
      end

      it "parses the ORDER attributes and its foreign key" do
        order = diagram.find_entity("ORDER")

        expect(order).not_to be_nil
        expect(order.attributes.length).to eq(3)
        expect(order.attributes[1].foreign_key?).to be true
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with multiple relationships of different cardinalities" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CUSTOMER ||--o{ ORDER
          ORDER ||--|{ LINE_ITEM
          PRODUCT ||--o{ LINE_ITEM
        MERMAID
      end

      it "parses every relationship and the four unique entities" do
        expect(diagram.relationships.length).to eq(3)
        expect(diagram.entities.map(&:id).sort)
          .to eq(%w[CUSTOMER LINE_ITEM ORDER PRODUCT])
      end

      it "parses the first relationship's cardinalities" do
        rel = diagram.relationships[0]

        expect(rel.cardinality_from).to eq("one")
        expect(rel.cardinality_to).to eq("zero_or_more")
      end

      it "parses the second relationship's cardinalities" do
        rel = diagram.relationships[1]

        expect(rel.cardinality_from).to eq("one")
        expect(rel.cardinality_to).to eq("one_or_more")
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with an identifying relationship" do
      let(:source) { "erDiagram\nCUSTOMER ||==o{ ORDER" }

      it "parses it as identifying" do
        expect(diagram.relationships.first.identifying?).to be true
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with a relationship without a label" do
      let(:source) { "erDiagram\nCUSTOMER ||--o{ ORDER" }

      it "parses it without a label" do
        expect(diagram.relationships.first.label).to be_nil
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with zero-or-one cardinality" do
      let(:source) { "erDiagram\nCUSTOMER ||--}o ADDRESS" }

      it "parses the cardinalities" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one")
        expect(rel.cardinality_to).to eq("zero_or_one")
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end
  end

  describe "classDef styles end to end" do
    let(:svg) { Sirena::Engine.new.render(source) }
    let(:doc) { REXML::Document.new(svg) }
    let(:rect) { doc.get_elements("//*[@id='entity-CAR']//rect").first }

    # The bucket case this branch clears: CAR gets one class (fill only),
    # PERSON gets two (fill and color). This is the oracle split measured
    # from spec/fixtures_mermaid/er_diagram/yari2-9471fb3f.svg.
    context "with the real corpus case (D1)" do
      let(:source) { File.read("spec/mermaid/er_diagram/yari2-9471fb3f.mmd") }

      it "renders an svg root" do
        expect(doc.root.name).to eq("svg")
      end

      it "renders both entities" do
        expect(entity_element(doc, "CAR")).not_to be_nil
        expect(entity_element(doc, "PERSON")).not_to be_nil
      end

      it "applies the entity fill to the CAR box" do
        car = entity_element(doc, "CAR")

        expect(car.get_elements(".//rect").first.attributes["fill"])
          .to eq("#f96")
      end

      it "applies the entity fill to the PERSON box" do
        person = entity_element(doc, "PERSON")

        expect(person.get_elements(".//rect").first.attributes["fill"])
          .to eq("#f96")
      end

      # `all()` on an empty array passes vacuously whatever the matcher, so
      # each side pins its text COUNT first (name + 3 attributes) and only
      # then asserts every fill. "Stated positively" alone does not close
      # this — an entity rendering zero text nodes would still pass either
      # polarity; only asserting the count does.
      it "colours every PERSON text node blue" do
        person = entity_element(doc, "PERSON")
        fills = person.get_elements(".//text").map { |t| t.attributes["fill"] }

        expect(fills.length).to eq(4)
        expect(fills).to all(eq("blue"))
      end

      it "colours every CAR text node with the default colour" do
        car = entity_element(doc, "CAR")
        fills = car.get_elements(".//text").map { |t| t.attributes["fill"] }

        expect(fills.length).to eq(4)
        expect(fills).to all(eq("#000000"))
      end
    end

    context "with a hostile style value (D2)" do
      let(:hostile) { '"><script>alert(1)</script>' }
      let(:source) { "erDiagram\nCAR:::a\nclassDef a fill:#{hostile}" }

      it "escapes the hostile style value" do
        expect(svg).not_to include("<script")
      end

      it "preserves the hostile style value verbatim" do
        expect(rect.attributes["fill"]).to eq(hostile)
      end
    end

    context "with a later classDef adding a new property (D3)" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CAR:::a
          classDef a fill:red
          classDef a stroke:blue
        MERMAID
      end

      it "keeps the earlier classDef property" do
        expect(rect.attributes["fill"]).to eq("red")
      end

      it "adds the later classDef property" do
        expect(rect.attributes["stroke"]).to eq("blue")
      end
    end

    # Verified against mermaid's own db: cssClasses is "default a b a" —
    # the trailing repeat of "a" wins on the conflicting fill.
    context "with a repeated class assignment (D4)" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CAR:::a,b
          CAR:::a
          classDef a fill:red
          classDef b fill:blue
        MERMAID
      end

      it "lets a repeated class assignment win in source order" do
        expect(rect.attributes["fill"]).to eq("red")
      end
    end

    # Verified against mermaid's own db: cssClasses is "default" for an
    # entity with no explicit assignment at all — a declared classDef
    # default applies to it anyway.
    context "with a declared classDef default (D5)" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CAR
          classDef default fill:red
        MERMAID
      end

      it "applies it with no explicit assignment" do
        expect(rect.attributes["fill"]).to eq("red")
      end
    end

    # Verified against mermaid's own db (stores "FILL:red" verbatim) and a
    # real browser (getComputedStyle resolves it to rgb(255, 0, 0) anyway,
    # since CSS property names are case-insensitive).
    context "with an upper-case classDef property (D6)" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CAR:::a
          classDef a FILL:red
        MERMAID
      end

      it "applies the property regardless of its declared case" do
        expect(rect.attributes["fill"]).to eq("red")
      end
    end
  end

  describe "attribute note end to end" do
    let(:doc) { REXML::Document.new(Sirena::Engine.new.render(source)) }

    # The High this branch fixes: the grammar already consumed the
    # trailing quoted comment, but nothing downstream carried it, so
    # mermaid-valid source like `int rental_id PK "NN"` silently lost the
    # comment on the way to SVG. Asserts on the rendered text itself, not
    # on an intermediate node surviving one layer.
    context "with a real corpus attribute note" do
      let(:source) { File.read("spec/mermaid/unknown/yari2-dc83acff.mmd") }
      let(:texts) { doc.get_elements("//text").map(&:text) }

      # 72 attributes in the source carry a "NN" note; a renderer that
      # drops all but one would still pass a bare `include` check, so this
      # asserts the full count survives.
      it "carries every note through to the rendered SVG" do
        expect(texts.count { |t| t =~ /\bNN\b/ })
          .to eq(source.scan('"NN"').length)
      end

      # inventory_id is rental's 2nd attribute: a note on a non-first one.
      it "carries a note on a non-first attribute" do
        expect(texts).to include(a_string_matching(/inventory_id.*NN/))
      end
    end

    context "with a minimal source" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK "NN"
          }
        MERMAID
      end

      it "renders the note" do
        texts = doc.get_elements("//*[@id='entity-RENTAL']//text").map(&:text)

        expect(texts).to include(a_string_matching(/\bNN\b/))
      end
    end
  end

  describe "DiagramRegistry integration" do
    it "has er_diagram registered" do
      expect(Sirena::DiagramRegistry.registered?(:er_diagram)).to be true
    end

    it "retrieves ER diagram handlers" do
      handlers = Sirena::DiagramRegistry.get(:er_diagram)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(described_class)
      expect(handlers[:transform]).to eq(Sirena::Layout::ErDiagram)
      expect(handlers[:renderer]).to eq(Sirena::Renderer::ErDiagram)
    end
  end
end
