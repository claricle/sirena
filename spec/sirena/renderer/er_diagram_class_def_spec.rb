# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::ErDiagramRenderer do
  let(:renderer) { described_class.new }

  def graph_with(class_defs:, entities:)
    {
      id: 'er_diagram',
      children: entities,
      edges: [],
      class_defs: class_defs
    }
  end

  def entity(id, classes:, attributed:)
    {
      id: id,
      x: 0,
      y: 0,
      width: 180,
      height: 100,
      metadata: {
        name: id,
        classes: classes,
        attributes: attributed ? [{ name: 'make', attribute_type: 'string', key_type: nil }] : []
      }
    }
  end

  def rect_for(svg, entity_id)
    group = svg.children.find { |c| c.is_a?(Sirena::Svg::Group) && c.id == "entity-#{entity_id}" }
    group.children.grep(Sirena::Svg::Rect).first
  end

  describe 'classDef style resolution, wired into the renderer' do
    it 'falls back to the plain box defaults when nothing declares a class' do
      graph = graph_with(class_defs: {}, entities: [entity('CAR', classes: [], attributed: false)])

      rect = rect_for(renderer.render(graph), 'CAR')

      expect(rect.fill).to eq('#f9f9f9')
      expect(rect.stroke).to eq('#333333')
      expect(rect.stroke_width).to eq('2')
    end

    it 'applies a classDef-declared fill to a bare entity' do
      graph = graph_with(
        class_defs: { 'a' => 'fill:#f96' },
        entities: [entity('CAR', classes: ['a'], attributed: false)]
      )

      rect = rect_for(renderer.render(graph), 'CAR')

      expect(rect.fill).to eq('#f96')
    end

    context 'when comparing the attributed and bare read strategies' do
      it "reads an attributed entity's fill by EXACT key — FILL (uppercase) never applies" do
        graph = graph_with(
          class_defs: { 'a' => 'FILL:blue' },
          entities: [entity('CAR', classes: ['a'], attributed: true)]
        )

        rect = rect_for(renderer.render(graph), 'CAR')

        expect(rect.fill).to eq('#f9f9f9') # falls through to the default
      end

      it "reads a bare entity's fill case-insensitively — FILL (uppercase) DOES apply" do
        graph = graph_with(
          class_defs: { 'a' => 'FILL:blue' },
          entities: [entity('CAR', classes: ['a'], attributed: false)]
        )

        rect = rect_for(renderer.render(graph), 'CAR')

        expect(rect.fill).to eq('blue')
      end
    end

    it "colors an entity's label text from the classDef-declared color" do
      graph = graph_with(
        class_defs: { 'a' => 'color:green' },
        entities: [entity('CAR', classes: ['a'], attributed: false)]
      )

      svg = renderer.render(graph)
      group = svg.children.find { |c| c.is_a?(Sirena::Svg::Group) && c.id == 'entity-CAR' }
      name_text = group.children.grep(Sirena::Svg::Text).first

      expect(name_text.fill).to eq('green')
    end

    it 'lets a later explicit class override an earlier one on a shared property' do
      graph = graph_with(
        class_defs: { 'default' => 'fill:#f9f9f9', 'a' => 'fill:red' },
        entities: [entity('CAR', classes: ['a'], attributed: false)]
      )

      rect = rect_for(renderer.render(graph), 'CAR')

      expect(rect.fill).to eq('red')
    end

    # D2: a hostile declared value must reach the rendered SVG attribute
    # VERBATIM and then be escaped by the XML serializer — never dropped
    # or substituted, on either read path.
    describe 'the D2 XSS-escaping contract' do
      let(:hostile) { '"><script>alert(1)</script>' }

      it 'escapes a hostile fill value on the attributed (exact-key) path' do
        graph = graph_with(
          class_defs: { 'a' => "fill:#{hostile}" },
          entities: [entity('CAR', classes: ['a'], attributed: true)]
        )

        xml = renderer.render(graph).to_xml

        expect(xml).to include(CGI.escapeHTML(hostile))
        expect(xml).not_to include('<script>')
      end

      it 'escapes a hostile fill value on the bare (cascade) path' do
        graph = graph_with(
          class_defs: { 'a' => "fill:#{hostile}" },
          entities: [entity('CAR', classes: ['a'], attributed: false)]
        )

        xml = renderer.render(graph).to_xml

        expect(xml).to include(CGI.escapeHTML(hostile))
        expect(xml).not_to include('<script>')
      end
    end
  end
end
