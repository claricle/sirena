# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  # The corpus cannot verify most of this. A naive version of this change —
  # widening `line_end` itself — passes the whole sweep and the whole suite
  # while breaking `style`, `classDef` and `click`, because no corpus case
  # puts a `;` inside a style property list. Every guard below is written by
  # hand against mmdc 11.12.0 for that reason.
  let(:engine) { Sirena::Engine.new }

  def renders?(source)
    engine.render(source)
    true
  rescue Sirena::Engine::PipelineError, Sirena::Engine::DiagramTypeError
    false
  end

  describe "accepting `;` as a separator" do
    {
      "after the header" => "graph TD;\nA-->B\n",
      "between statements on one line" => "graph TD\nA-->B;C-->D\n",
      "with leading whitespace" => "graph TD\nA-->B ;C\n",
      "repeated" => "graph TD\nA-->B;;;C\n",
      "on the header and repeated" => "graph TD;;A-->B;;;C-->D;;\n",
      "trailing before EOF" => "graph TD\nA-->B;\n"
    }.each do |label, source|
      it "accepts a separator #{label}" do
        expect(renders?(source)).to be(true)
      end
    end
  end

  describe "rules that scan to the physical end of a line" do
    # These four render on main and in mmdc. They are the regressions the
    # rejected design would have caused: both rules are written as
    # `line_end.absent?`, so widening `line_end` truncates them at the `;`.
    {
      "style with two properties" =>
        "graph TD\nA-->B\nstyle A fill:#f9f;stroke:#333\n",
      "classDef with two properties" =>
        "graph TD\nA-->B\nclassDef foo fill:#f9f;stroke:#333\n",
      "click with a semicolon in the URL" =>
        %(graph TD\nA\nclick A "https://example.com/a;b"\n),
      "click mixing bare tokens and quoted strings" =>
        %(graph TD\nA\nclick A href "https://example.com/a;b" "tip;here" _blank\n)
    }.each do |label, source|
      it "still renders #{label}" do
        expect(renders?(source)).to be(true)
      end
    end
  end

  describe "click keeps its own terminator" do
    it "rejects an actionless click followed by a separator" do
      # `click_action` is optional, so pointing click's terminator at
      # `statement_end` would parse this as an actionless click plus a node.
      # mmdc rejects it, because click requires an action.
      expect(renders?("graph TD\nA\nB\nclick A;B\n")).to be(false)
    end
  end

  describe "the separator rule itself" do
    # `statement_end` must never be repeated directly: its `line_end` arm
    # succeeds zero-width at EOF, so repeating it would spin forever. These
    # two hang rather than fail if that is got wrong, which is why they are
    # asserted at the parser rather than through the engine — a node-less
    # flowchart is rejected downstream on main too, for unrelated reasons.
    it "terminates on a header followed only by separators" do
      expect { described_class.new.parse("graph TD;;;\n") }.not_to raise_error
    end

    it "terminates on separators at end of input" do
      expect { described_class.new.parse("graph TD\nA-->B;;;") }
        .not_to raise_error
    end
  end
end
