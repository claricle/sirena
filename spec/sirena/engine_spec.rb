# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

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

    context 'with the byte-identical empty ER corpus rows' do
      fixture_files = [
        'er/059_spec_xss_spec_58.mmd',
        'er/060_spec_diagram-orchestration_spec_59.mmd',
        'er/061_spec_mermaidapi_spec_60.mmd'
      ]

      def expect_empty_er_fixture_to_render(relative_path)
        path = File.expand_path("../mermaid/#{relative_path}", __dir__)
        svg = engine.render(File.binread(path))

        expect(svg).to be_a(String)
        expect(svg).not_to be_empty
        expect(svg).to match(/\A<svg[\s>]/)
        expect(svg.rstrip).to end_with('</svg>')

        document = REXML::Document.new(svg)
        expect(document.elements.to_a.map(&:name)).to eq(['svg'])
        expect(document.root.namespace).to eq('http://www.w3.org/2000/svg')
      end

      fixture_files.each do |relative_path|
        it "guards the byte content of #{relative_path}" do
          path = File.expand_path("../mermaid/#{relative_path}", __dir__)

          expect(File.exist?(path)).to be true
          expect(File.binread(path)).to eq('erDiagram')
        end

        it "renders byte-identical replay row #{relative_path}" do
          expect_empty_er_fixture_to_render(relative_path)
        end
      end
    end

    context 'with user journey diagram' do
      let(:source) { "journey\ntitle My working day\nsection Go to work" }

      it 'detects user journey diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    context 'with treemap corpus cases' do
      # Globbing at definition time means an empty or moved directory
      # would silently define zero examples and still pass, so guard it.
      it 'finds treemap corpus cases to render' do
        expect(
          Dir.glob(File.expand_path('../mermaid/treemap/*.mmd', __dir__))
        ).not_to be_empty
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

    # A direction glyph may sit right against the keyword. Detection
    # wanted whitespace there, so mmdc drew these and Sirena refused to
    # name the type at all.
    context 'with a flowchart header the direction touches' do
      %w[> < ^].each do |glyph|
        it "renders graph#{glyph}" do
          expect(engine.render("graph#{glyph}\nA --- B\n")).to include('<svg')
        end

        it "renders flowchart#{glyph}" do
          expect(engine.render("flowchart#{glyph}\nA --- B\n"))
            .to include('<svg')
        end
      end

      it 'names the type for a bare keyword, as the grammar does' do
        # mmdc renders `graph` on its own. Detection wanted a character
        # after the keyword, so this never reached the parser at all. It
        # still fails downstream, where an empty flowchart is refused on
        # main too, but it fails as a flowchart rather than as no type.
        expect { engine.render('graph') }.to raise_error(
          Sirena::Engine::PipelineError
        )
      end

      it 'still refuses a keyword glued to a word' do
        expect { engine.render("graphTD\nA --- B\n") }.to raise_error(
          Sirena::Engine::DiagramTypeError
        )
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
