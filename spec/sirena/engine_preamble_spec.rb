# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Engine do
  # Every example here goes through Engine#render on purpose. The split
  # happens inside render, so a spec written against a parser directly would
  # pass without exercising any of this.
  let(:engine) { described_class.new }

  def slices
    %(  "Dogs" : 50\n  "Cats" : 30\n)
  end

  describe "#render with a preamble" do
    it "detects the type behind a frontmatter block" do
      xml = engine.render("---\ntitle: T\n---\nflowchart LR\n  A-->B\n")

      expect(xml).to include("<svg")
    end

    it "detects the type behind a %%{init}%% directive" do
      xml = engine.render(
        %(%%{init: {"theme":"base"}}%%\nsequenceDiagram\n  A->>B: m\n)
      )

      expect(xml).to include("<svg")
    end

    it "detects the type behind a %% comment" do
      xml = engine.render("%% a note\nclassDiagram\n  class C1\n")

      expect(xml).to include("<svg")
    end

    it "still raises when the source is nothing but a preamble" do
      expect { engine.render("---\ntitle: T\n---\n") }
        .to raise_error(described_class::DiagramTypeError)
    end

    it "still raises for an indented frontmatter closer" do
      # mmdc rejects it, so the 44 corpus cases shaped this way must keep
      # failing rather than be rescued by a lenient fence.
      source = "---\n  config:\n    theme: base\n  ---\n  flowchart LR\n  A-->B\n"

      expect { engine.render(source) }
        .to raise_error(described_class::DiagramTypeError)
    end
  end

  describe "#render frontmatter title" do
    # Pie draws its title into the SVG, so precedence is observable in the
    # output rather than through a stub. The corpus sweep cannot see any of
    # this — it only checks the SVG is well formed.
    def titles_in(source)
      engine.render(source).scan(%r{<text[^>]*>([^<]*)</text>}).flatten
    end

    it "sets the title from frontmatter" do
      titles = titles_in("---\ntitle: From Front\n---\npie\n#{slices}")

      expect(titles.first).to eq("From Front")
    end

    it "does not overwrite a title the body already set" do
      source = "---\ntitle: From Front\n---\npie title From Body\n#{slices}"

      expect(titles_in(source).first).to eq("From Body")
    end

    it "leaves the title unset when the frontmatter has none" do
      titles = titles_in("---\nconfig:\n  theme: base\n---\npie\n#{slices}")

      expect(titles).to eq(%w[Dogs Cats])
    end
  end

  describe "#render with malformed frontmatter" do
    it "is refused even when the body supplies its own title" do
      # Reading the title only when the body had none meant malformed YAML
      # was never validated for a diagram that titled itself. mmdc rejects
      # the source either way.
      source = "---\ntitle: [\n---\npie title Body\n#{slices}"

      expect { engine.render(source) }
        .to raise_error(described_class::PipelineError, /frontmatter/i)
    end

    it "is refused when the body has no title either" do
      expect { engine.render("---\ntitle: [\n---\npie\n#{slices}") }
        .to raise_error(described_class::PipelineError, /frontmatter/i)
    end
  end

  describe "#render with a directive that is not one" do
    it "refuses a body with no word token" do
      # `%%{!}%%` is not a directive. mmdc rejects it in front of a
      # flowchart and renders it in front of the lenient types, so the
      # refusal belongs to the type rather than to the split.
      expect { engine.render("%%{!}%%\nflowchart LR\n  A-->B\n") }
        .to raise_error(described_class::PipelineError, /does not accept/)
    end

    it "does not let an empty one reach a later terminator" do
      # `(.+?)` could not stop at the empty directive's own `}%%`, so the
      # scan ran on and rendered a LATER diagram in the file.
      source = "%%{}%%\nflowchart LR\n  A-->B\n%% x }%%\nflowchart TD\n"

      expect { engine.render(source) }
        .to raise_error(described_class::PipelineError, /does not accept/)
    end

    # Only the standalone shape is type-dependent. mmdc refuses the
    # inline and the multiline shape for every one of the 23 types —
    # measured, six directive shapes against all 23. sequenceDiagram
    # renders `%%{}%%` on a line of its own and refuses both of these.
    # Both bodies are here because it is the missing header that takes
    # the line, not an empty body — gating on empty renders `%%{!}%%`
    # inline, and mmdc refuses that too.
    ["%%{}%%", "%%{!}%%"].each do |directive|
      it "refuses #{directive} sharing a line with the body" do
        expect { engine.render("#{directive}sequenceDiagram\n  A->>B: m\n") }
          .to raise_error(described_class::DiagramTypeError)
      end
    end

    it "refuses a headerless directive spread over two lines" do
      expect { engine.render("%%{\n}%%\nsequenceDiagram\n  A->>B: m\n") }
        .to raise_error(described_class::DiagramTypeError)
    end

    # What decides it is what the line eats, not whether anything follows
    # the terminator. A `%%` comment behind it goes with the line and
    # costs the body nothing, so this is still the standalone shape —
    # mmdc renders it in front of sequenceDiagram.
    it "renders when only a comment follows the terminator" do
      expect { engine.render("%%{}%%%% note\nsequenceDiagram\n  A->>B: m\n") }
        .not_to raise_error
    end

    # An unterminated `%%{}` is a comment line, so the diagram behind it
    # survives. Holding out for a `}%%` left the `%%{` in the body and
    # refused a source mmdc renders.
    it "renders a sequence diagram behind an unterminated one" do
      expect { engine.render("%%{}\nsequenceDiagram\n  A->>B: m\n") }
        .not_to raise_error
    end

    it "still refuses one in front of a flowchart" do
      expect { engine.render("%%{}\nflowchart LR\n  A-->B\n") }
        .to raise_error(described_class::PipelineError, /does not accept/)
    end

    # With a header word it IS a directive, terminator or not, and it
    # swallows what it matched. mmdc refuses this file for the same reason:
    # the diagram went with the directive.
    it "refuses a blob value that never closes" do
      expect { engine.render("%%{init: {}\nsequenceDiagram\n  A->>B: m\n") }
        .to raise_error(described_class::DiagramTypeError)
    end

    it "renders behind a bare-word value that never closes" do
      expect { engine.render("%%{init: x\nsequenceDiagram\n  A->>B: m\n") }
        .not_to raise_error
    end

    it "stops at its own terminator, whatever follows later" do
      # The real guard for the `(.*?)` fix. Asserted on the split rather
      # than the render, because an overrun leaves a body that starts at
      # the LATER diagram — and that is what the scan must not do,
      # whether or not the whole file parses.
      source = "%%{}%%\nsequenceDiagram\n  A->>B: first\n" \
               "%% x }%%\nflowchart TD\n  C-->D\n"

      expect(Sirena::Source.split(source)[:body])
        .to start_with("sequenceDiagram")
    end
  end

  describe "#render refusal enumerations" do
    let(:empty_preamble_forms) do
      {
        "%%\n" => "an empty comment",
        "%%{}%%\n" => "a directive with no header"
      }
    end

    {
      flowchart: "flowchart LR\n  A-->B\n",
      er_diagram: "erDiagram\n  A ||--o{ B : has\n",
      user_journey: "journey\n  section S\n  Task: 5: A\n",
      gantt: "gantt\n  dateFormat YYYY-MM-DD\n  section S\n  T: 2024-01-01, 1d\n",
      timeline: "timeline\n  2024 : Event\n",
      block: "block-beta\n  A\n",
      sankey: "sankey-beta\nA,B,1\n",
      requirement: "requirementDiagram\n"
    }.each do |type, body|
      it "refuses both empty preamble forms for #{type}" do
        empty_preamble_forms.each do |preamble, reason|
          expect { engine.render("#{preamble}#{body}") }
            .to raise_error(
              described_class::PipelineError,
              /\ARendering failed: A #{type} diagram does not accept #{reason}\./
            )
        end
      end
    end

    it "refuses a headerless directive for state_diagram" do
      source = "%%{}%%\nstateDiagram-v2\n  [*] --> S\n"

      expect { engine.render(source) }
        .to raise_error(
          described_class::PipelineError,
          /\ARendering failed: A state_diagram diagram does not accept a directive with no header\./
        )
    end

    {
      flowchart: "flowchart LR\n  A-->B\n",
      sequence: "sequenceDiagram\n  A->>B: m\n",
      class_diagram: "classDiagram\n  class A\n",
      state_diagram: "stateDiagram-v2\n  [*] --> S\n",
      er_diagram: "erDiagram\n  A ||--o{ B : has\n",
      user_journey: "journey\n  section S\n  Task: 5: A\n",
      gantt: "gantt\n  dateFormat YYYY-MM-DD\n  section S\n  T: 2024-01-01, 1d\n",
      timeline: "timeline\n  2024 : Event\n",
      quadrant: "quadrantChart\n  A: [0.5, 0.5]\n",
      mindmap: "mindmap\n  root((A))\n",
      kanban: "kanban\n  column1[Todo]\n    task1[Task]\n",
      block: "block-beta\n  A\n",
      requirement: "requirementDiagram\n",
      xychart: "xychart-beta\n  x-axis [1, 2]\n  line [1, 2]\n",
      sankey: "sankey-beta\nA,B,1\n",
      treemap: "treemap-beta\n\"A\": 1\n",
      c4: "C4Context\n  Person(a, \"A\")\n"
    }.each do |type, body|
      it "refuses late frontmatter for #{type}" do
        source = "%% note\n---\ntitle: T\n---\n#{body}"

        expect { engine.render(source) }
          .to raise_error(
            described_class::PipelineError,
            /\ARendering failed: A #{type} diagram does not accept frontmatter behind another item\./
          )
      end
    end
  end

  describe "#render with a fence that is not at the start" do
    # A fence behind anything at all is not frontmatter to mermaid. The
    # lines stay in the text, so the diagram's own parser meets them:
    # seventeen types stop there and six skip them. Stripping it for
    # everyone rendered seventeen types' worth of sources mmdc refuses —
    # measured, every registered type with the fence behind a comment.
    it "refuses one in front of a flowchart" do
      source = "%% a\n---\ntitle: T\n---\nflowchart LR\n  A-->B\n"

      expect { engine.render(source) }
        .to raise_error(described_class::PipelineError, /does not accept/)
    end

    it "refuses one in front of a sequence diagram" do
      source = "\n---\ntitle: T\n---\nsequenceDiagram\n  A->>B: m\n"

      expect { engine.render(source) }
        .to raise_error(described_class::PipelineError, /does not accept/)
    end

    it "renders one in front of a pie chart" do
      source = "%% a\n---\ntitle: T\n---\npie\n#{slices}"

      expect(engine.render(source)).to include("<svg")
    end

    it "draws no title from it" do
      # mmdc draws the pie and no title: the block is never read.
      source = "%% a\n---\ntitle: From Front\n---\npie\n#{slices}"

      expect(engine.render(source)).not_to include("From Front")
    end

    it "refuses a second fence in front of a flowchart" do
      source = "---\ntitle: T\n---\n---\ntitle: U\n---\nflowchart LR\n  A-->B\n"

      expect { engine.render(source) }
        .to raise_error(described_class::PipelineError, /does not accept/)
    end

    it "still draws the first fence's title on a pie behind a second" do
      source = "---\ntitle: First\n---\n---\ntitle: U\n---\npie\n#{slices}"

      xml = engine.render(source)

      expect(xml).to include("First")
      expect(xml).not_to include(">U<")
    end
  end

  describe "#render types with no title of their own" do
    # Both models gained a title slot so the engine-level assignment is
    # uniform; without it, setting a frontmatter title raised NoMethodError
    # on two types that pass today.
    #
    # Neither renderer DRAWS a title, on this branch or on main — 10 of the
    # 24 renderers do. That is a pre-existing gap in those renderers, not
    # something this change introduces, and the assertions below say only
    # that the diagrams render.
    it "renders a block diagram carrying a frontmatter title" do
      xml = engine.render("---\ntitle: T\n---\nblock-beta\n  A\n")

      expect(xml).to include("<svg")
    end

    it "renders a requirement diagram carrying a frontmatter title" do
      source = "---\ntitle: T\n---\nrequirementDiagram\n" \
               "requirement R {\nid: 1\ntext: t\nrisk: low\n" \
               "verifymethod: test\n}\n"

      expect(engine.render(source)).to include("<svg")
    end
  end
end
