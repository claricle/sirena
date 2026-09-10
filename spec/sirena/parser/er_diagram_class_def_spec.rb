# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::ErDiagramParser do
  let(:parser) { described_class.new }

  describe '#parse with classDef and :::' do
    it 'records a classDef declaration by name' do
      source = "erDiagram\nCAR\nclassDef a fill:#f96,stroke:#333"
      diagram = parser.parse(source)

      expect(diagram.class_defs).to eq({ 'a' => 'fill:#f96,stroke:#333' })
    end

    it 'strips an optional trailing semicolon from the style text, not just the newline' do
      source = "erDiagram\nCAR\nclassDef a fill:#f96;"
      diagram = parser.parse(source)

      expect(diagram.class_defs['a']).to eq('fill:#f96')
    end

    it 'accumulates a repeated classDef for the same name, comma-joined, instead of replacing it' do
      source = "erDiagram\nCAR\nclassDef a fill:red\nclassDef a stroke:green"
      diagram = parser.parse(source)

      expect(diagram.class_defs['a']).to eq('fill:red,stroke:green')
    end

    it 'assigns a class to a bare entity declaration via :::' do
      source = "erDiagram\nCAR:::a"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(['a'])
    end

    it 'assigns a class to an entity with an attribute block via :::' do
      source = "erDiagram\nCAR:::a {\n  string make\n}"
      diagram = parser.parse(source)

      entity = diagram.find_entity('CAR')
      expect(entity.classes).to eq(['a'])
      expect(entity.attributes.map(&:name)).to eq(['make'])
    end

    it 'assigns classes independently on both ends of a relationship' do
      source = "erDiagram\nCUSTOMER:::a ||--o{ ORDER:::b : places"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CUSTOMER').classes).to eq(['a'])
      expect(diagram.find_entity('ORDER').classes).to eq(['b'])
    end

    it 'accepts multiple comma-separated classes in one ::: assignment' do
      source = "erDiagram\nCAR:::a,b"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'does NOT dedupe a repeated ::: assignment across statements' do
      source = "erDiagram\nCAR:::a,b\nCAR:::a"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b a])
    end
  end
end
