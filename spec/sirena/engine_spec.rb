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

    context 'with an empty ER diagram' do
      # The bare keyword, which is all three empty rows of the ER corpus
      # hold: spec/mermaid/er/059, 060 and 061.
      let(:source) { 'erDiagram' }

      let(:document) { REXML::Document.new(engine.render(source)) }

      # mmdc renders this source at viewBox="-8 -8 16 16", max-width 16px.
      # Sirena keeps its own "0 0" origin and matches the 16x16 extent.
      it 'renders the 16x16 empty canvas with nothing in it' do
        expect(document.root.attributes['width']).to eq('16.0')
        expect(document.root.attributes['height']).to eq('16.0')
        expect(document.root.attributes['viewBox']).to eq('0 0 16 16')
        expect(document.root.elements.to_a).to eq([])
      end
    end

    context 'with user journey diagram' do
      let(:source) { "journey\ntitle My working day\nsection Go to work" }

      it 'detects user journey diagram type' do
        expect { engine.render(source) }.not_to raise_error
      end
    end

    # :corpus - sweeps the whole fixture directory and only asserts the
    # output looks SVG-shaped. Runs in `spec:corpus`, isolated from the
    # coverage-collecting `spec:unit` run: see .simplecov and
    # lib/tasks/coverage.rake.
    context 'with treemap corpus cases', :corpus do
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
        # The failure is the transform's own validity check, so it now
        # propagates as TransformError rather than being collapsed into
        # PipelineError (see the error-taxonomy fix in engine.rb).
        expect { engine.render('graph') }.to raise_error(
          Sirena::Transform::TransformError
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

  # Regression lock for the leading-directive detection gap that
  # fix/init-directive-detection set out to fix: `Source.split` (merged via
  # #15) already reads a diagram type past a `%%{init}%%` directive or a
  # `%%` comment before `Engine` ever sees the raw source -- these pin that
  # behaviour through the real production path rather than the
  # since-superseded `detectable_source` this PR originally added.
  #
  # NOT covered here, and confirmed still broken on this exact tip:
  # NBSP/em-space directive openers, a BOM behind a comment line, a doubled
  # `%%{%%{` opener, U+2028/U+2029 inside a directive body, and non-UTF-8
  # tagged source (ISO-8859-1/UTF-16LE/ASCII-8BIT/invalid-UTF-8 bytes) --
  # the last raises a raw Encoding::CompatibilityError/ArgumentError out of
  # Source.split or detect_diagram_type, caught only by #render's blanket
  # StandardError rescue. Flagged separately; out of scope for this pass.
  describe 'diagram type detection past a leading directive or comment' do
    let(:engine) { described_class.new }

    def detect(source)
      preamble = Sirena::Source.split(source)
      engine.send(:detect_diagram_type, preamble[:body])
    end

    [
      ['a single leading directive',
       "%%{init: {'theme':'dark'}}%%\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['two stacked directives',
       "%%{init: {'theme':'dark'}}%%\n%%{wrap}%%\nsequenceDiagram\n" \
       "Alice->>Bob: hi\n",
       :sequence],
      ['a directive with blank lines around it',
       "\n%%{init: {'theme':'dark'}}%%\n\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['an indented directive',
       "   %%{init: {'theme':'dark'}}%%\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['a directive broken over lines',
       "%%{init: {\n  'theme':'dark'\n}}%%\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['a directive and the header on one line',
       "%%{init: {'theme':'dark'}}%% sequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['CRLF line endings',
       "%%{init: {'theme':'dark'}}%%\r\nsequenceDiagram\r\nAlice->>Bob: hi\r\n",
       :sequence],
      ['a directive after the header',
       "sequenceDiagram\n%%{init: {'theme':'dark'}}%%\nAlice->>Bob: hi\n",
       :sequence],
      ['a plain comment before the header',
       "%% just a note\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['a comment ended by a bare carriage return',
       "%% note\rsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['a directive whose body names another diagram type',
       "%%{init: {'themeCSS':'flowchart'}}%%\nsequenceDiagram\n" \
       "Alice->>Bob: hi\n",
       :sequence],
      ['a directive above a flowchart',
       "%%{init: {'theme':'dark'}}%%\nflowchart TD\nA-->B\n",
       :flowchart],
      ['a directive above a class diagram',
       "%%{init: {'theme':'dark'}}%%\nclassDiagram\nA <|-- B\n",
       :class_diagram],
      ['two directives sharing the header line',
       "%%{init: {'theme':'dark'}}%%%%{init: {'look':'classic'}}%% " \
       "sequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['two comment lines above the header',
       "%% a\n%% b\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['a colonless directive on the header line',
       "%%{wrap}%% sequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['an uppercase directive keyword',
       "%%{INIT: {'theme':'dark'}}%%\nsequenceDiagram\nAlice->>Bob: hi\n",
       :sequence],
      ['a bare comment line with nothing after it',
       "%%\nflowchart TD\nA-->B\n",
       :flowchart]
    ].each do |name, source, expected|
      it "names #{expected} past #{name}" do
        expect(detect(source)).to eq(expected)
      end
    end

    [
      ['a directive left unterminated, which swallows the header',
       "%%{init: {'theme':'dark'}\nsequenceDiagram\nAlice->>Bob: hi\n"],
      ['a bare carriage return that keeps the header off the first line',
       "%% a\rb\nsequenceDiagram\nAlice->>Bob: hi\n"],
      ['a comment splitting a keyword in half',
       "sequence%% x\nDiagram\nAlice->>Bob: hi\n"],
      ['a comment splitting the flowchart keyword in half',
       "flow%% c\nchart TD\nA-->B\n"]
    ].each do |name, source|
      it "still refuses #{name}" do
        expect { detect(source) }.to raise_error(
          described_class::DiagramTypeError
        )
      end
    end

    it 'draws a directive sharing the header line, end to end' do
      # Source.split lifts the directive off the body entirely (into
      # preamble[:directives]), so the parser never sees it -- unlike the
      # old detectable_source approach, this never depended on the
      # grammar's own comment rule to skip it, and there is no rendering
      # gap left to pin for this shape.
      svg = engine.render(
        "%%{init: {'theme':'dark'}}%% sequenceDiagram\nAlice->>Bob: hi\n"
      )

      expect(svg).to include('Alice').and include('Bob')
    end
  end
end
