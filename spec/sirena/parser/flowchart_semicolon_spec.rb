# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  # The corpus cannot verify most of this. A naive version of this change —
  # widening `line_end` itself — passes the whole sweep and the whole suite
  # while breaking `style`, `classDef` and `click`, because no corpus case
  # puts a `;` inside a style property list. Every guard below is written by
  # hand against mmdc 11.12.0 for that reason.
  let(:engine) { Sirena::Engine.new }

  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

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

  describe "statements after a separator survive" do
    # Scanning a value to the end of the line swallowed whatever followed a
    # `;`, so these parsed and then silently rendered one node short. mmdc
    # renders B in every case. Asserted on the model, because the render
    # succeeds either way and the corpus scores it a pass.
    {
      "style" => "graph TD\nA\nstyle A fill:#f9f;B\n",
      "classDef" => "graph TD\nA\nclassDef x fill:#f9f;B\n",
      "click" => %(graph TD\nA\nclick A "http://x";B\n)
    }.each do |label, source|
      it "keeps a node after a #{label} statement" do
        expect(node_ids(source)).to eq(%w[A B])
      end
    end

    it "still reads two declarations as one list" do
      expect(node_ids("graph TD\nA-->B\nstyle A fill:#f9f;stroke:#333\n"))
        .to eq(%w[A B])
    end
  end

  describe "click requires an action" do
    # mmdc rejects a bare `click A`, so an optional action let a separator
    # turn `click A;B` into an actionless click plus a node.
    it "rejects a bare click" do
      expect(renders?("graph TD\nA\nclick A\n")).to be(false)
    end

    it "rejects an actionless click followed by a separator" do
      expect(renders?("graph TD\nA\nB\nclick A;B\n")).to be(false)
    end
  end

  describe "declarations mermaid accepts loosely" do
    # Requiring `name:value` here rejected five forms main accepted and mmdc
    # renders. Only the decision after a `;` is strict now.
    [
      "style A  fill:red",
      "style A fill :red",
      "style A fill:",
      "style A red",
      "classDef x red"
    ].each do |declaration|
      it "still accepts #{declaration.inspect}" do
        expect(renders?("graph TD\nA\n#{declaration}\n")).to be(true)
      end
    end
  end

  describe "a statement keyword is not a node" do
    # A malformed directive used to fall through to the node rules, so
    # `click ;B` produced nodes `click` and `B`. mmdc rejects all of these.
    ["click ;B", "style ;B", "class ;B"].each do |source|
      it "rejects #{source.inspect}" do
        expect(renders?("graph TD\nA\nB\n#{source}\n")).to be(false)
      end
    end

    it "leaves a node whose name merely starts with a keyword alone" do
      expect(renders?("graph TD\nendpoint-->classy\n")).to be(true)
    end
  end

  describe "a space before the separator" do
    # mmdc takes it on a node statement and refuses it on the header or a
    # class assignment, so one shared separator over-accepted two forms.
    it "is allowed on a node statement" do
      expect(renders?("graph TD\nA-->B ;C\n")).to be(true)
    end

    it "is refused on the header" do
      expect(renders?("graph TD ;A\n")).to be(false)
    end

    it "is refused on a class assignment" do
      expect(renders?("graph TD\nA\nB\nclass A foo ;B\n")).to be(false)
    end

    it "is refused between a click action and the separator" do
      # The action ran up to the space and left ` ;B` for the terminator,
      # which produced a node B. mmdc rejects the source outright.
      expect(renders?(%(graph TD\nA\nclick A "u" ;B\n))).to be(false)
    end
  end

  describe "a colon that is not a declaration" do
    # The continuation lookahead took any text before a colon, so a node
    # label containing one looked like another property and got swallowed.
    {
      "style" => "graph TD\nA\nstyle A fill:red;B(foo:bar)\n",
      "classDef" => "graph TD\nA\nclassDef x f:r;B(foo:bar)\n"
    }.each do |label, source|
      it "keeps a node with a colon in its label after #{label}" do
        expect(node_ids(source)).to eq(%w[A B])
      end
    end
  end

  describe "a semicolon inside a callback argument" do
    it "belongs to the callback, not the statement" do
      expect(renders?("graph TD\nA\nclick A call cb(foo;bar)\n")).to be(true)
    end

    it "still separates after the closing paren" do
      source = "graph TD\nA\nclick A call cb(foo;bar);B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end
  end

  describe "click before an unspaced separator" do
    it "is a node, as mmdc renders it" do
      expect(node_ids("graph TD;click;B\n")).to eq(%w[B click])
    end
  end

  describe "a comment on the same line as a separator" do
    # mmdc rejects the same-line form and takes the newline form. `space?`
    # never crosses a newline, so one guard separates them.
    [
      "graph TD;%% c;D",
      "graph TD\nA;;%% c;D",
      "graph TD\nA ;%% c;D",
      "graph TD\nA;%% c;D"
    ].each do |source|
      it "rejects #{source.lines.last.chomp.inspect}" do
        expect(renders?("#{source}\n")).to be(false)
      end
    end

    it "still takes a comment on the next line" do
      expect(renders?("graph TD\nA-->B;\n%% comment\n")).to be(true)
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
