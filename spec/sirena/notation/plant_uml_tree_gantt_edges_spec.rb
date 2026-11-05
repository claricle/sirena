# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# The edges of the PlantUML mindmap, work breakdown and gantt readers and
# layouts that the corpus fixtures do not reach, each from inline source.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:svg) { Sirena.render(source) }
  let(:texts) do
    REXML::XPath.match(REXML::Document.new(svg).root,
                       "//*[local-name()='text']").map do |text|
      text.texts.map(&:value).join
    end
  end
  let(:refused) { Sirena::Notation::PlantUML::UnsupportedConstructError }

  context "with a mindmap that carries a title, an empty box and tails" do
    let(:source) do
      "@startmindmap\ntitle Plan\n* Root\n**:\n;\n**: one;\n" \
        "**:first\ntail;\n@endmindmap\n"
    end

    it "skips the title and keeps every box's text" do
      expect(texts).to include("Root", "one", "first", "tail")
    end

    it "does not draw the title as a node" do
      expect(texts).not_to include("title Plan", "Plan")
    end
  end

  context "with a style class that sets no background" do
    let(:source) do
      "@startmindmap\n<style>\n.plain { LineColor red }\n</style>\n" \
        "* Root <<plain>>\n@endmindmap\n"
    end

    it "leaves the box unfilled and still reads the text" do
      expect(texts).to include("Root")
    end
  end

  context "with a lone work breakdown root" do
    let(:source) { "@startwbs\n* Alone\n@endwbs\n" }

    it "draws the root" do
      expect(texts).to eq(["Alone"])
    end
  end

  context "with a work breakdown root and one child" do
    let(:source) { "@startwbs\n* Root\n** Only\n@endwbs\n" }

    it "draws both" do
      expect(texts).to contain_exactly("Root", "Only")
    end
  end

  context "with a gantt that skips a title and sets dates and an alias" do
    let(:source) do
      "@startgantt\ntitle Plan\n[A] as [X] starts 2020-01-05 and ends " \
        "2020-01-10\n[B] starts at [X]'s end and is 40% completed\n" \
        "then [C] requires 2 days\n@endgantt\n"
    end

    it "draws the tasks" do
      expect(texts).to include("A", "B", "C")
    end

    it "does not draw the title as a task" do
      expect(texts).not_to include("title Plan")
    end
  end

  context "with a gantt statement outside the subset" do
    let(:source) { "@startgantt\nnonsense here\n@endgantt\n" }

    it "refuses it by name" do
      expect { svg }.to raise_error(refused, /gantt statement/)
    end
  end

  context "with an unknown gantt clause" do
    let(:source) { "@startgantt\n[A] frobnicates\n@endgantt\n" }

    it "refuses it by name" do
      expect { svg }.to raise_error(refused, /gantt clause/)
    end
  end
end
