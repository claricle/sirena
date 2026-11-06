# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# The plugin corpus (claricle/metanorma-plugin-sirena) mindmap fixtures 17-2,
# 17-3, 17-4 and 17-6-3, work breakdown fixtures 18-1 and 18-7, and gantt
# fixture 16-1-1, verbatim, rendered by auto-detection as the plugin does.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:svg) { Sirena.render(source) }
  let(:root) { REXML::Document.new(svg).root }
  let(:texts) do
    REXML::XPath.match(root, "//*[local-name()='text']").map do |text|
      text.texts.map(&:value).join
    end
  end
  let(:rects) do
    REXML::XPath.match(root, "//*[local-name()='rect']").map do |rect|
      rect_keys.map { |name| rect.attributes[name].to_f }
    end
  end

  def text_named(label)
    REXML::XPath.match(root, "//*[local-name()='text']")
      .find { |text| text.texts.map(&:value).join == label }
  end

  def family_of(label)
    text_named(label).attributes["font-family"]
  end

  def rect_keys
    %w[x y width height]
  end

  # The box that holds the text, by its label.
  def box_for(label)
    text = REXML::XPath.match(root, "//*[local-name()='text']").find do |item|
      item.texts.map(&:value).join == label
    end
    point = %w[x y].map { |name| text.attributes[name].to_f }
    rects.find { |rect| contains?(rect, *point) }
  end

  def contains?(rect, x_pos, y_pos)
    left, top, width, height = rect
    left < x_pos && x_pos < left + width && top < y_pos && y_pos < top + height
  end

  def centre_x(box)
    box[0] + (box[2] / 2)
  end

  def centre_y(label)
    box = box_for(label)
    box[1] + (box[3] / 2)
  end

  def right_of(label)
    box = box_for(label)
    box[0] + box[2]
  end

  context "with fixture 17-2, mindmap roots" do
    let(:source) do
      <<~PUML
        @startmindmap
        * root node
        * some first level node
        * second level node
        * another second level node
        * another first level node
        @endmindmap
      PUML
    end

    it "draws each first-level line as a box of its own, in order" do
      expect(texts).to eq(["root node", "some first level node",
                           "second level node", "another second level node",
                           "another first level node"])
    end

    it "stacks the boxes top to bottom with nothing joining them" do
      tops = rects.map { |rect| rect[1] }
      expect([tops, REXML::XPath.match(root, "//*[local-name()='path']")])
        .to eq([tops.sort, []])
    end
  end

  context "with fixture 17-3, plus and minus sides" do
    let(:source) do
      <<~PUML
        @startmindmap
        + OS
        ++ Ubuntu
        +++ Linux Mint
        +++ Kubuntu
        +++ Lubuntu
        +++ KDE Neon
        ++ LMDE
        ++ SolydXK
        ++ SteamOS
        ++ Raspbian
        -- Windows 95
        -- Windows 98
        -- Windows NT
        --- Windows 8
        --- Windows 10
        @endmindmap
      PUML
    end

    it "draws every label" do
      expect(texts).to include("OS", "Linux Mint", "KDE Neon", "Windows 95",
                               "Windows 10", "Raspbian")
    end

    it "grows the minus branches left of the root and the plus ones right" do
      root_box = box_for("OS")
      expect([box_for("Windows 95")[0] < root_box[0],
              box_for("Ubuntu")[0] > root_box[0] + root_box[2]])
        .to eq([true, true])
    end

    it "puts a grandchild further out than its parent" do
      expect([box_for("Linux Mint")[0] > right_of("Ubuntu"),
              right_of("Windows 8") < box_for("Windows NT")[0]])
        .to eq([true, true])
    end

    it "centres a parent on what hangs from it" do
      expect(centre_y("Ubuntu"))
        .to be_within(0.5)
        .of((centre_y("Linux Mint") + centre_y("KDE Neon")) / 2)
    end

    it "keeps siblings that have no children one box and a gap apart" do
      expect(centre_y("SolydXK") - centre_y("LMDE"))
        .to be_within(0.5).of(56.488)
    end

    it "joins every parent to every child" do
      paths = REXML::XPath.match(root, "//*[local-name()='path']")
      expect(paths.length).to eq(14)
    end
  end

  context "with fixture 17-4, multi-line nodes" do
    let(:source) do
      <<~PUML
        @startmindmap
        * Class Templates
        **:Example 1
        <code>
        template <typename T>
        class cname{
        void f1()<U+003B>
        ...
        }
        </code>
        ;
        **:Example 2
        <code>
        other template <typename T>
        class cname{
        ...
        </code>
        ;
        @endmindmap
      PUML
    end

    it "draws each line of a node as its own line of text" do
      expect(texts).to include("Example 1", "template <typename T>",
                               "void f1()<U+003B>", "Example 2",
                               "other template <typename T>")
    end

    it "drops the code tags" do
      expect(texts.grep(/code/)).to be_empty
    end

    it "draws the code lines in monospace and the rest in sans-serif" do
      expect([family_of("Example 1"), family_of("template <typename T>")])
        .to eq(%w[sans-serif monospace])
    end

    it "sizes the box from DejaVu Sans Mono (JAR: 177.0029 + 20)" do
      widths = REXML::XPath.match(root, "//*[local-name()='rect']")
        .map { |rect| rect.attributes["width"].to_f }
      expect(widths).to include(be_within(0.001).of(197.003))
    end

    it "pitches code lines at the monospace line height (JAR 16.297)" do
      ys = ["template <typename T>", "class cname{"].map do |label|
        text_named(label).attributes["y"].to_f
      end
      expect(ys.last - ys.first).to be_within(0.002).of(16.297)
    end
  end

  context "with a code line that ends the node" do
    let(:source) do
      "@startmindmap\n* root\n**:a\n<code>\nx = 1;\n@endmindmap\n"
    end

    it "draws the closing line in monospace" do
      expect(family_of("x = 1")).to eq("monospace")
    end
  end

  context "with fixture 17-6-3, style classes" do
    let(:source) do
      <<~PUML
        @startmindmap
        <style>
        mindmapDiagram {
          .green {
            BackgroundColor lightgreen
          }
          .rose {
            BackgroundColor #FFBBCC
          }
          .your_style_name {
            BackgroundColor lightblue
          }
        }
        </style>
        * root node
        * some first level node <<green>>
        * second level node <<rose>>
        * another second level node <<your_style_name>>
        * another first level node <<green>>
        @endmindmap
      PUML
    end

    it "fills each box with its class's colour" do
      fills = REXML::XPath.match(root, "//*[local-name()='rect']")
        .map { |rect| rect.attributes["fill"] }
      expect(fills).to eq(["#F1F1F1", "lightgreen", "#ffbbcc", "lightblue",
                           "lightgreen"])
    end

    it "does not draw the class name" do
      expect(texts).to include("some first level node")
        .and(satisfy { |all| all.none? { |text| text.include?("<<") } })
    end
  end

  context "with fixture 18-1, a work breakdown structure" do
    let(:source) do
      <<~PUML
        @startwbs
        * Business Process Modelling WBS
        ** Launch the project
        *** Complete Stakeholder Research
        *** Initial Implementation Plan
        ** Design phase
        *** Model of AsIs Processes Completed
        **** Model of AsIs Processes Completed1
        **** Model of AsIs Processes Completed2
        *** Measure AsIs performance metrics
        *** Identify Quick Wins
        ** Complete innovate phase
        @endwbs
      PUML
    end

    it "draws every label" do
      expect(texts.length).to eq(11)
    end

    it "puts the first level in a row under the root" do
      tops = ["Launch the project", "Design phase", "Complete innovate phase"]
        .map { |label| box_for(label)[1] }
      expect([tops.uniq.length,
              tops.first > box_for("Business Process Modelling WBS")[1]])
        .to eq([1, true])
    end

    it "hangs deeper levels in a column under their parent, to its right" do
      parent = box_for("Design phase")
      child = box_for("Model of AsIs Processes Completed")
      expect([child[1] > parent[1] + parent[3],
              child[0] > parent[0] + (parent[2] / 2)])
        .to eq([true, true])
    end

    it "centres the root over its first-level boxes" do
      first = box_for("Launch the project")
      last = box_for("Complete innovate phase")
      root_box = box_for("Business Process Modelling WBS")
      expect(centre_x(root_box))
        .to be_within(0.5).of((centre_x(first) + centre_x(last)) / 2)
    end

    it "keeps the boxes of different branches apart" do
      overlap = rects.combination(2).any? do |one, other|
        one[0] < other[0] + other[2] && other[0] < one[0] + one[2] &&
          one[1] < other[1] + other[3] && other[1] < one[1] + one[3]
      end
      expect(overlap).to be(false)
    end
  end

  context "with fixture 18-7, a styled breakdown with sides and no boxes" do
    let(:source) do
      <<~PUML
        @startwbs
        <style>
        wbsDiagram {
          // all lines (meaning connector and borders, there are no other lines in WBS) are black by default
          Linecolor black
          arrow {
            LineColor green
          }
          :depth(0) {
            BackgroundColor White
            RoundCorner 10
            LineColor red
          }
          boxless {
            // will target boxless node with '_'
            FontColor darkgreen
          }
        }
        </style>
        * World
        ** America
        *** Canada
        *** Mexico
        **** Chihuahua
        *** USA
        **** Texas
        ***< New York
        ** Europe
        ***_ England
        ***_ Germany
        ***_ Spain
        @endwbs
      PUML
    end

    it "draws every label" do
      expect(texts).to include("World", "America", "New York", "Chihuahua",
                               "England", "Spain")
    end

    it "hangs a node marked with < to the left of its parent's line" do
      america = box_for("America")
      centre = america[0] + (america[2] / 2)
      expect([right_of("New York") < centre, box_for("Canada")[0] > centre])
        .to eq([true, true])
    end

    it "draws no box for a node marked with _" do
      expect([box_for("England"), box_for("Spain")]).to eq([nil, nil])
    end

    it "draws a box for every other node" do
      expect(rects.length).to eq(9)
    end
  end

  context "with fixture 16-1-1, a gantt chart" do
    let(:source) do
      <<~PUML
        @startgantt
        [Prototype design] requires 15 days
        [Test prototype] requires 10 days
        -- All example --
        [Task 1 (1 day)] requires 1 day
        [T2 (5 days)] requires 5 days
        [T3 (1 week)] requires 1 week
        [T4 (1 week and 4 days)] requires 1 week and 4 days
        [T5 (2 weeks)] requires 2 weeks
        @endgantt
      PUML
    end

    it "draws every task name and the section title" do
      expect(texts).to include("Prototype design", "Test prototype",
                               "All example", "Task 1 (1 day)",
                               "T4 (1 week and 4 days)", "T5 (2 weeks)")
    end

    it "draws no table of start, end and duration beside the chart" do
      expect(texts & ["Start", "End", "Duration", "Day 15", "15 days"])
        .to be_empty
    end

    it "numbers the days above and below the grid" do
      expect(texts.grep(/\A\d+\z/)).to eq((1..15).map(&:to_s) * 2)
    end

    it "begins the grid at the left edge" do
      expect(rects.map { |rect| rect[0] }.uniq).to eq([2.0])
    end

    it "draws a bar a day wide per day of the task, less the gap" do
      bars = rects.map { |rect| rect[2] }
      expect(bars).to eq([236.0, 156.0, 12.0, 76.0, 108.0, 172.0, 220.0])
    end

    it "starts every bar on the first day" do
      expect(rects.map { |rect| rect[0] }.uniq.length).to eq(1)
    end
  end

  context "with gantt dependencies and dates" do
    let(:source) do
      <<~PUML
        @startgantt
        Project starts 2020-07-01
        [Design] requires 3 days
        [Build] requires 2 days
        [Design] -> [Build]
        [Ship] happens 2020-07-10
        @endgantt
      PUML
    end

    it "keeps the dated table with each task's first and last day" do
      expect(texts).to include("2020-07-01", "2020-07-03", "2020-07-04",
                               "2020-07-05")
    end

    it "draws a milestone as a diamond" do
      expect(REXML::XPath.match(root, "//*[local-name()='polygon']").length)
        .to eq(1)
    end
  end

  context "with a gantt clause outside the subset" do
    let(:source) { "@startgantt\n[A] starts at [B]'s start\n@endgantt\n" }

    it "refuses it by name" do
      expect { svg }.to raise_error(
        Sirena::Notation::PlantUML::UnsupportedConstructError, /gantt clause/
      )
    end
  end

  context "with a mindmap line outside the subset" do
    let(:source) { "@startmindmap\nnot a node\n@endmindmap\n" }

    it "refuses it with its line" do
      expect { svg }.to raise_error(
        Sirena::Notation::PlantUML::UnsupportedConstructError, /line 2/
      )
    end
  end

  describe "claiming" do
    it "claims a mindmap, a work breakdown and a gantt opener" do
      claimed = %w[mindmap wbs gantt].map do |kind|
        described_class.claims?("@start#{kind}\n@end#{kind}\n")
      end
      expect(claimed).to eq([true, true, true])
    end

    it "does not claim a tag that merely begins like one" do
      expect(described_class.claims?("@startwbsx\n")).to be(false)
    end
  end
end
