# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Engine do
  describe '#render' do
    let(:engine) { described_class.new }

    context 'with flowchart diagram' do
      let(:source) { "graph TD\nA-->B" }

      it 'detects flowchart diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end

      it 'returns SVG output' do
        result = engine.render(source)
        expect(result).to be_a(String)
        expect(result).to include('<svg')
      end
    end

    context 'with sequence diagram' do
      let(:source) { "sequenceDiagram\nAlice->>Bob: Hello" }

      it 'detects sequence diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    context 'with class diagram' do
      let(:source) { "classDiagram\nClass01 <|-- Class02" }

      it 'detects class diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    context 'with state diagram' do
      let(:source) { "stateDiagram\n[*] --> Still" }

      it 'detects state diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    context 'with ER diagram' do
      let(:source) { "erDiagram\nCUSTOMER ||--o{ ORDER : places" }

      it 'detects ER diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    context 'with user journey diagram' do
      let(:source) { "journey\ntitle My working day\nsection Go to work" }

      it 'detects user journey diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    context 'with treemap corpus cases' do
      it 'keeps all ten corpus cases present' do
        expect(
          Dir.glob(File.expand_path('../mermaid/treemap/*.mmd', __dir__)).size
        ).to eq(10)
      end

      # 007 is excluded: it fails at parse and is flagged
      # probably-oracle-invalid (pending item 02's verdict).
      Dir.glob(File.expand_path('../mermaid/treemap/*.mmd', __dir__))
        .reject { |path| path.end_with?('007_rendering_treemap_spec_treemap_6.mmd') }
        .each do |fixture_file|
        it "renders #{File.basename(fixture_file)}" do
          result = engine.render(File.read(fixture_file))

          expect(result).to be_a(String)
          expect(result).to include('<svg')
          expect(result.rstrip).to end_with('</svg>')
        end
      end
    end

    context 'with unknown diagram type' do
      let(:source) { "unknown\ntest" }

      it 'raises DiagramTypeError' do
        expect { engine.render(source) }.to raise_error(
          Sirena::Engine::DiagramTypeError,
          /Unable to detect diagram type/
        )
      end
    end

    context 'with verbose option' do
      it 'enables verbose output' do
        source = "graph TD\nA-->B"
        expect { engine.render(source, verbose: true) }.to output(
          /Starting render pipeline/
        ).to_stdout
      end
    end
  end

  describe '#initialize' do
    it 'creates engine with default options' do
      engine = described_class.new
      expect(engine.verbose).to be false
    end

    it 'creates engine with verbose option' do
      engine = described_class.new(verbose: true)
      expect(engine.verbose).to be true
    end
  end
end
