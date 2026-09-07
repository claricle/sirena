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

  # Mermaid deletes `%%{init: ...}%%` directives and `%%` comments before it
  # looks for a diagram keyword, so a source that opens with one still names
  # its type. Detection here read the source as written and raised
  # DiagramTypeError instead, which killed 31 corpus cases across four types
  # before the parser -- which already reads both constructs -- ever saw them.
  #
  # These assert the detected TYPE rather than the rendered SVG, because the
  # type is the property and the SVG is a symptom of it. Going through
  # #render would also conflate detection with parsing: the bare-CR row below
  # detects :sequence and then fails in the grammar, whose `newline` rule
  # takes "\n" and "\r\n" and not a lone "\r".
  describe 'diagram type detection' do
    let(:engine) { described_class.new }

    # A `def` here is scoped to this example group. `let` cannot take an
    # argument -- `let(:x) { |a| a }` yields the RSpec example, not the
    # source -- and a `def` at file level would land on Object and be
    # visible to every other spec file in the suite.
    def detect(source)
      engine.send(:detect_diagram_type, source)
    end

    # Every row is a shape mmdc 11.12.0 renders. The decoy row is the sharp
    # one: `flowchart` is the FIRST entry in DIAGRAM_TYPE_PATTERNS, so a
    # strip that left the directive's body behind would answer :flowchart
    # for a sequence diagram rather than merely failing.
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
       :class_diagram]
    ].each do |name, source, expected|
      it "names #{expected} past #{name}" do
        expect(detect(source)).to eq(expected)
      end
    end

    # The refusals matter as much as the detections: a strip that merely
    # deleted every line opening with `%%` would answer :sequence for the
    # first three of these, and mmdc refuses all four.
    [
      ['a directive with no diagram after it',
       "%%{init: {'theme':'dark'}}%%\n"],
      ['a directive left unterminated, which swallows the header',
       "%%{init: {'theme':'dark'}\nsequenceDiagram\nAlice->>Bob: hi\n"],
      ['a bare carriage return that keeps the header off the first line',
       "%% a\rb\nsequenceDiagram\nAlice->>Bob: hi\n"],
      ['a comment and a directive over an unknown keyword',
       "%% note\n%%{init: {'theme':'dark'}}%%\nnonsense\nA-->B\n"]
    ].each do |name, source|
      it "still refuses #{name}" do
        expect { detect(source) }.to raise_error(
          described_class::DiagramTypeError
        )
      end
    end

    it 'draws a directive-carrying source end to end' do
      # Detection was the whole gap, so this is the payoff: the same source
      # that raised DiagramTypeError now reaches the renderer. The
      # assertion names the drawn participants rather than `<svg>`, which
      # an empty document would also satisfy.
      #
      # It deliberately does NOT claim to prove the parser gets the source
      # as written. The grammars read a directive as a comment, so the
      # stripped copy would draw the same picture, and no assertion here
      # could tell the two apart.
      svg = engine.render(
        "%%{init: {'theme':'dark'}}%%\nsequenceDiagram\nAlice->>Bob: hi\n"
      )

      expect(svg).to include('Alice').and include('Bob')
    end
  end
end
