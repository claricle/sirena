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
  end
end
