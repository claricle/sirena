# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Style do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def svg(*lines)
    xml = Sirena::Engine.new.render("@startuml\n#{lines.join("\n")}\n@enduml\n")
    REXML::Document.new(xml).root
  end

  def first(root, xpath)
    REXML::XPath.first(root, xpath)
  end

  def group(root, id)
    first(root, "//*[local-name()='g'][@id='#{id}']")
  end

  def attrs(element, *names)
    names.map { |name| element.attributes[name] }
  end

  describe "a state diagram" do
    let(:state_block) do
      ["skinparam state {", "BackgroundColor LightYellow", "BorderColor Navy",
       "RoundCorner 4", "}"]
    end
    let(:composite) { ["state Comp {", "[*] --> A", "}", "[*] --> Comp"] }

    it "draws PlantUML's default look when the source sets nothing" do
      rect = first(group(svg(*composite), "state-A"), "*[local-name()='rect']")

      expect(attrs(rect, "fill", "stroke", "stroke-width"))
        .to eq(["#F1F1F1", "#181818", "0.5"])
    end

    it "draws the composite's name in a header bar closed by a rule" do
      comp = group(svg(*composite), "state-Comp")

      expect(first(comp, "*[local-name()='line']")).not_to be_nil
    end

    it "fills only the name band of a composite and leaves its body clear" do
      comp = group(svg(*composite), "state-Comp")
      band = first(comp, ".//*[local-name()='path']")
      frame = first(comp, ".//*[local-name()='rect']")

      expect([band.attributes["fill"], frame.attributes["fill"]])
        .to eq(["#F1F1F1", "none"])
    end

    it "closes the composite's band at its divider" do
      comp = group(svg(*composite), "state-Comp")
      band = first(comp, ".//*[local-name()='path']").attributes["d"]
      rule = first(comp, "*[local-name()='line']").attributes["y1"].to_f
      bottoms = band.scan(/L(\S+),(\S+)/).map { |_, y| y.to_f }

      expect(bottoms).to include(rule)
    end

    it "fills the whole composite when the source sets its colour" do
      comp = group(svg("state Comp #pink {", "[*] --> A", "}"), "state-Comp")
      fill = first(comp, ".//*[local-name()='rect']").attributes["fill"]

      expect(fill).to eq("#FFC0CB")
    end

    it "applies BackgroundColor, BorderColor and RoundCorner from skinparam" do
      rect = first(group(svg(*state_block, "state A"), "state-A"),
                   "*[local-name()='rect']")

      expect(attrs(rect, "fill", "stroke", "rx"))
        .to eq(["#FFFFE0", "#000080", "4.0"])
    end

    it "applies FontColor and FontName to the label" do
      root = svg("skinparam stateFontColor DarkGreen",
                 "skinparam stateFontName Courier", "[*] --> A")
      text = first(group(root, "state-A"), "*[local-name()='text']")

      expect(attrs(text, "fill", "font-family"))
        .to eq(["#006400", "Courier"])
    end

    it "applies LineStyle dotted from <style>" do
      root = svg("<style>", "state {", "LineStyle dotted", "}", "</style>",
                 "[*] --> A")
      rect = first(group(root, "state-A"), "*[local-name()='rect']")

      expect(rect.attributes["stroke-dasharray"]).to eq("1,3")
    end

    it "colours one state with #red and leaves its neighbour alone" do
      root = svg("state A #red", "state B", "A --> B")
      fills = %w[state-A state-B].map do |id|
        first(group(root, id), "*[local-name()='rect']").attributes["fill"]
      end

      expect(fills).to eq(["#FF0000", "#F1F1F1"])
    end

    it "applies ##[dashed]blue as a dashed blue border on one state" do
      rect = first(group(svg("state A ##[dashed]blue"), "state-A"),
                   "*[local-name()='rect']")

      expect(attrs(rect, "stroke", "stroke-dasharray"))
        .to eq(["#0000FF", "7,7"])
    end

    it "draws the end state's ring and dot in the start colours" do
      root = svg("[*] --> A", "A --> [*]")
      ring, dot = REXML::XPath.match(group(root, "state-root_end"),
                                     ".//*[local-name()='circle']")

      expect([ring.attributes["stroke"], dot.attributes["fill"]])
        .to eq(%w[#222222 #222222])
    end

    it "gives a transition label the arrow's font" do
      root = svg("skinparam ArrowFontName Courier", "[*] --> A : go")

      expect(root.to_s).to include("Courier")
    end

    it "reads a dashed line modifier after the colour" do
      rect = first(group(svg("state A #pink;line.dashed"), "state-A"),
                   "*[local-name()='rect']")

      expect(attrs(rect, "fill", "stroke-dasharray")).to eq(["#FFC0CB", "7,7"])
    end

    it "ignores a non-numeric RoundCorner" do
      root = svg("skinparam roundCorner abc", "[*] --> A")

      expect(group(root, "state-A")).not_to be_nil
    end

    it "applies ArrowColor to the transitions" do
      root = svg("skinparam ArrowColor Red", "[*] --> A")
      path = first(group(root, "transition-root_start_to_A"),
                   "*[local-name()='path']")

      expect(path.attributes["stroke"]).to eq("#FF0000")
    end

    it "paints the canvas from skinparam backgroundColor" do
      root = svg("skinparam backgroundColor #EEE", "[*] --> A")

      expect(first(root, "*[local-name()='rect']").attributes["fill"])
        .to eq("#EEEEEE")
    end
  end

  describe "a class diagram" do
    def class_rect(root, name)
      first(group(root, "class-#{name}"), "*[local-name()='rect']")
    end

    it "draws PlantUML's default look when the source sets nothing" do
      expect(attrs(class_rect(svg("class A"), "A"), "fill", "stroke"))
        .to eq(["#F1F1F1", "#181818"])
    end

    it "applies the skinparam class block" do
      root = svg("skinparam class {", "BackgroundColor LightYellow",
                 "BorderColor Navy", "RoundCorner 10", "}", "class A")

      expect(attrs(class_rect(root, "A"), "fill", "stroke", "rx"))
        .to eq(["#FFFFE0", "#000080", "10.0"])
    end

    it "applies FontName and FontColor to every text of the class" do
      root = svg("skinparam classFontName Courier",
                 "skinparam classFontColor DarkGreen", "class A {", "+x", "}")
      texts = REXML::XPath.match(group(root, "class-A"), "*[name()='text']")

      expect(texts.map { |t| attrs(t, "fill", "font-family") }.uniq)
        .to eq([["#006400", "Courier"]])
    end

    it "applies LineStyle dashed from <style>" do
      root = svg("<style>", "classDiagram {", "class {", "LineStyle dashed",
                 "}", "}", "</style>", "class A")

      expect(class_rect(root, "A").attributes["stroke-dasharray"])
        .to eq("7,7")
    end

    it "colours one class with #red and not its neighbour" do
      root = svg("class A #red", "class B", "A --> B")

      expect(%w[A B].map { |n| class_rect(root, n).attributes["fill"] })
        .to eq(["#FF0000", "#F1F1F1"])
    end

    it "applies ArrowColor to a relation" do
      root = svg("skinparam ArrowColor Red", "class A", "class B", "A --> B")
      path = first(group(root, "relation-0"), "*[local-name()='path']")

      expect(path.attributes["stroke"]).to eq("#FF0000")
    end
  end

  describe "an activity diagram" do
    let(:flow) { ["start", ":hello;", "stop"] }

    def action_rect(root)
      first(root, "//*[local-name()='rect']")
    end

    it "keeps its default look when the source sets nothing" do
      expect(attrs(action_rect(svg(*flow)), "fill", "stroke"))
        .to eq(["#F1F1F1", "#181818"])
    end

    it "applies the skinparam activity block" do
      root = svg("skinparam activity {", "BackgroundColor LightYellow",
                 "BorderColor Navy", "RoundCorner 3", "}", *flow)

      expect(attrs(action_rect(root), "fill", "stroke", "rx"))
        .to eq(["#FFFFE0", "#000080", "3.0"])
    end

    it "applies FontColor and FontName to the text" do
      root = svg("skinparam activityFontColor DarkGreen",
                 "skinparam activityFontName Courier", *flow)
      text = first(root, "//*[local-name()='text']")

      expect(attrs(text, "fill", "font-family"))
        .to eq(["#006400", "Courier"])
    end

    it "applies a <style> activityDiagram block" do
      root = svg("<style>", "activityDiagram {", "BackgroundColor #ccf",
                 "LineStyle dotted", "}", "</style>", *flow)

      expect(attrs(action_rect(root), "fill", "stroke-dasharray"))
        .to eq(["#CCCCFF", "1,3"])
    end

    it "keeps an action's own #colour over the style" do
      root = svg("skinparam activityBackgroundColor pink", "start",
                 "#red:hello;", "stop")

      expect(action_rect(root).attributes["fill"]).not_to eq("#FFC0CB")
    end

    it "applies ArrowColor to the flow lines" do
      root = svg("skinparam ArrowColor Red", *flow)
      path = first(root, "//*[local-name()='path']")

      expect(path.attributes["stroke"]).to eq("#FF0000")
    end

    describe "element selectors of a <style> sheet" do
      let(:sheet) do
        ["<style>", "activityDiagram {", "BackgroundColor #33668E",
         "FontColor #888", "diamond {", "BackgroundColor #ccf",
         "LineColor #00FF00", "FontColor green", "}", "arrow {",
         "FontColor gold", "}", "partition {", "LineColor red",
         "FontColor green", "RoundCorner 10", "BackgroundColor PeachPuff", "}",
         "note {", "FontColor Blue", "LineColor Navy",
         "BackgroundColor #ccf", "}", "}", "</style>"]
      end
      let(:flow) do
        ["start", "if (ok?) then (yes)", ":a;", "note right: n", "endif",
         "partition P {", ":b;", "}", "-> done;", "stop"]
      end
      let(:root) { svg(*sheet, *flow) }

      def shapes(xpath)
        REXML::XPath.match(root, xpath)
      end

      def widths_of(tag)
        shapes("//*[local-name()='#{tag}']")
          .map { |s| s.attributes["stroke-width"] }.uniq.sort
      end

      def text_fill(content)
        shapes("//*[local-name()='text']")
          .find { |t| t.text == content }.attributes["fill"]
      end

      def diamonds
        sides = [4, 6]
        shapes("//*[local-name()='polygon'][@fill='#CCCCFF']").select do |poly|
          sides.include?(poly.attributes["points"].split.size)
        end
      end

      it "paints every diamond with the diamond rule" do
        expect(diamonds.map { |p| p.attributes["stroke"] })
          .to eq(%w[#00FF00 #00FF00])
      end

      it "colours the decision text with the diamond FontColor" do
        expect(text_fill("ok?")).to eq("#008000")
      end

      it "colours arrow labels with the arrow FontColor" do
        expect(text_fill("done")).to eq("#FFD700")
      end

      it "draws the partition with its own paint and half its RoundCorner" do
        frame = shapes("//*[local-name()='rect'][@fill='#FFDAB9']").first

        expect(attrs(frame, "stroke", "rx")).to eq(["#FF0000", "5.0"])
      end

      it "colours the partition title with the partition FontColor" do
        expect(text_fill("P")).to eq("#008000")
      end

      it "paints the note with the note rule" do
        note = shapes("//*[local-name()='polygon'][@stroke='#000080']").first

        expect([note.attributes["fill"], text_fill("n")])
          .to eq(["#CCCCFF", "#0000FF"])
      end

      it "leaves the actions to the activityDiagram block" do
        action = first(root, "//*[local-name()='rect'][@rx='12.5']")

        expect([action.attributes["fill"], text_fill("a")])
          .to eq(["#33668E", "#888888"])
      end

      it "draws partitions at 1.5 and boxes, diamonds and notes at 0.5" do
        widths = %w[rect polygon].map { |tag| widths_of(tag) }

        expect(widths).to eq([%w[0.5 1.5], %w[0.5 1]])
      end

      it "ignores BorderColor in a <style> block" do
        plain = svg("<style>", "activityDiagram {", "BorderColor red", "}",
                    "</style>", *flow)
        rect = first(plain, "//*[local-name()='rect'][@rx='12.5']")

        expect(rect.attributes["stroke"]).to eq("#181818")
      end

      it "still honours BorderColor in skinparam" do
        plain = svg("skinparam activityBorderColor red", *flow)
        rect = first(plain, "//*[local-name()='rect'][@rx='12.5']")

        expect(rect.attributes["stroke"]).to eq("#FF0000")
      end

      it "cascades the root LineColor to arrows, start and stop" do
        plain = svg("<style>", "activityDiagram {", "LineColor #112233", "}",
                    "</style>", "start", ":a;", "stop")
        marks = "//*[local-name()='path' or local-name()='circle']"
        strokes = REXML::XPath.match(plain, marks).map { |e| e["stroke"] }

        expect(strokes.uniq).to eq(["#112233"])
      end

      it "fills the start disc with the root BackgroundColor" do
        disc = first(root, "//*[local-name()='circle'][@r='10.0']")

        expect(disc.attributes["fill"]).to eq("#33668E")
      end

      it "leaves arrows and the start disc alone under skinparam" do
        plain = svg("skinparam activityBorderColor red",
                    "skinparam activityBackgroundColor pink", *flow)
        disc = first(plain, "//*[local-name()='circle'][@r='10.0']")
        path = first(plain, "//*[local-name()='path']")

        expect([disc["fill"], path["stroke"]]).to eq(%w[#222222 #181818])
      end

      it "keeps the default look of notes and diamonds without a rule" do
        plain = svg("<style>", "activityDiagram {", "BackgroundColor pink",
                    "}", "</style>", *flow)
        note = REXML::XPath.match(plain, "//*[local-name()='polygon']")
          .find { |p| p.attributes["fill"] == "#FEFFDD" }

        expect(note).not_to be_nil
      end
    end
  end
end
