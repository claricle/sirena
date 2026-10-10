# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Requiring the notation registers it; restore the suite's baseline here and
# register inside the isolated context, as the class notation's spec does.
Sirena::Notation.send(:entries).delete(:plantuml)

module PlantUmlSequenceCorpus
  DIR = File.expand_path("../../../plantuml/sequence", __dir__)

  # The 12-hex suffix of every case of spec/plantuml/sequence the slice
  # renders today. A case joins this list when it renders; it never leaves it.
  RENDERED = %w[
    61e71ad8eca5 18b03e1b811e 5bbc1c2fa32b da4311bd2115 e1598e37241a
    cd27c406b434 3e3df0d464c3 ebbf246498ea d4b4359acf05 d086f0811a32
    833298c44032 6b4f8cacde95 7d1d5500d228 1a24d5f462c1 c797d0cd3eab
    6ef262c9c97b a4059b3b3ee9 459b540cd94b 41e5a7ff94cb 14a816e0bd6e
    1a2e8a0dbc73 0742b0602928 9efe4ddda292 b0355d4c2434 9d48b2180ff0
    5dbc30d9717f f121a37a9290 9617d3aa3c9f fb338498bd7e 4965c575d64a
    9edd3c67e417 671c16bf124d 8f71f44c46ac b74549f2f6be
    3d52db0edecd 54dfdd51ac5d 62b7d8792525 7624adcaae49 80894b73726a
    846af1d12917 920d4bcaa3e9 d783321e2c62
    559333843e38 184d55bcfb9c 2dd4eecfa67b f985a9b8f0de
    0385427ea4be 24072f84b995 577feb6055fb 4f6a53784edf 4f323bdad314
    5bcc726e80b1 af2e98871d2d a4a8af9cba7c 29dfa779f376
    6893700e037a 18d6381b866f f602d00329ee
    7ff458de0156 2a2a7bb5aacc f0cf331472b7 e76e451484c6
    ddc664f08110 d918f796209f ae1299794d0b fcaf69429c9c
    bea0f11e448b 2bd5234bfbfe 2018ad068c81 f0cb24bd16e0
    ad11bf4b448a 793d6e993975 1f75ab64bf5e e6d99fb6ac3c 1f8e5fb51e4d
    a13609de5404 990470abe6d9
  ].freeze

  def case_named(suffix)
    Dir.glob(File.join(DIR, "*--#{suffix}.puml")).first
  end

  def source_of(suffix)
    File.read(case_named(suffix))
  end

  def unread_cases
    Dir.glob(File.join(DIR, "*.puml")).reject do |path|
      RENDERED.any? { |suffix| path.end_with?("--#{suffix}.puml") }
    end
  end

  def rect_count(svg)
    matches(svg, "//rect").size
  end

  def matches(svg, xpath)
    REXML::XPath.match(REXML::Document.new(svg), xpath)
  end

  def refusal(path)
    Sirena.render(File.read(path), notation: :plantuml)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError,
         Sirena::Parser::ParseError => e
    e
  end
end

RSpec.describe Sirena::Notation::PlantUML::Sequence do
  include PlantUmlSequenceCorpus

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  PlantUmlSequenceCorpus::RENDERED.each do |name|
    it "renders well-formed SVG for case #{name}" do
      svg = Sirena.render(source_of(name), notation: :plantuml)

      expect(REXML::Document.new(svg).root.name).to eq("svg")
    end
  end

  it "draws one lifeline per declared participant in a rendered case" do
    name = "0742b0602928"
    svg = Sirena.render(source_of(name), notation: :plantuml)

    expect(REXML::XPath.match(REXML::Document.new(svg), "//line").size).to eq(2)
  end

  it "draws the activation bar of a rendered case" do
    source = source_of("7624adcaae49")
    counts = [source, source.gsub(/^(de)?activate .*\n/, "")].map do |text|
      rect_count(Sirena.render(text, notation: :plantuml))
    end

    expect(counts.first - counts.last).to eq(1)
  end

  it "fills a coloured note, folded corner included" do
    svg = Sirena.render("@startuml\nA -> B\nnote right #red: x\n@enduml\n",
                        notation: :plantuml)

    expect(matches(svg, "//path/@fill").map(&:value).count("#FF0000")).to eq(2)
  end

  it "draws the opacity of a note colour with an alpha" do
    source = "@startuml\nA -> B\nnote right #ff000080: x\n@enduml\n"
    svg = Sirena.render(source, notation: :plantuml)

    expect(matches(svg, "//path/@fill-opacity").map(&:value).uniq)
      .to eq(["0.50196"])
  end

  it "draws a cross for a destroyed participant of a rendered case" do
    source = source_of("184d55bcfb9c")
    counts = [source, source.sub(/^destroy .*\n/, "")].map do |text|
      matches(Sirena.render(text, notation: :plantuml), "//line").size
    end

    expect(counts.first - counts.last).to eq(2)
  end

  it "widens the heads of a case that sets a minimum width" do
    widths = %w[24072f84b995 577feb6055fb].map do |name|
      svg = Sirena.render(source_of(name), notation: :plantuml)
      matches(svg, "//rect/@width").map { |w| w.value.to_f }.max
    end

    expect(widths).to all(be >= 114.0)
  end

  it "fills the tab of the group header case with its style colours" do
    svg = Sirena.render(source_of("5bcc726e80b1"), notation: :plantuml)
    fills = matches(svg, "//path/@fill").map(&:value)

    expect(fills).to include("#FFFFE0")
  end

  it "colours the group tab text of that case" do
    svg = Sirena.render(source_of("5bcc726e80b1"), notation: :plantuml)

    expect(matches(svg, "//text[.='Setup']/@fill").map(&:value))
      .to eq(["#0000FF"])
  end

  it "draws the group tab of the nested-over-flat case at the flat size" do
    svg = Sirena.render(source_of("29dfa779f376"), notation: :plantuml)

    expect(matches(svg, "//text[.='Setup']/@font-size").map(&:value))
      .to eq(["20.0"])
  end

  it "keeps the flat colours when the nested header sets another" do
    svg = Sirena.render(source_of("29dfa779f376"), notation: :plantuml)

    expect(matches(svg, "//text[.='Setup']/@fill").map(&:value))
      .to eq(["#0000FF"])
  end

  it "draws the nested-header group exactly as the unstyled one" do
    nested = Sirena.render(source_of("af2e98871d2d"), notation: :plantuml)
    bare = source_of("af2e98871d2d").sub(%r{<style>.*</style>\n}m, "")

    expect(nested).to eq(Sirena.render(bare, notation: :plantuml))
  end

  it "draws the stereotype of the left-aligned case at the block edge" do
    svg = Sirena.render(source_of("4f6a53784edf"), notation: :plantuml)

    expect(matches(svg, "//text[.='«st»']/@text-anchor").map(&:value).uniq)
      .to eq(["start"])
  end

  it "fills the bar of a rendered case with its colour" do
    svg = Sirena.render(source_of("2dd4eecfa67b"), notation: :plantuml)
    fills = matches(svg, "//rect/@fill").map(&:value)

    expect(fills).to include("red", "green")
  end

  it "draws the parallel notes of a rendered case at one height" do
    svg = Sirena.render(source_of("f602d00329ee"), notation: :plantuml)
    ys = matches(svg, "//text[starts-with(., 'n')]/@y").map(&:value)

    expect([ys.size, ys.uniq.size]).to eq([4, 1])
  end

  it "draws the foot heads of a rendered case only without hide footbox" do
    source = source_of("f0cf331472b7")
    counts = [source, source.sub(/^hide footbox\n/, "")].map do |text|
      rect_count(Sirena.render(text, notation: :plantuml))
    end

    expect(counts.last - counts.first).to eq(2)
  end

  it "draws the warning banner of the note-top-on-ref case" do
    svg = Sirena.render(source_of("1f75ab64bf5e"), notation: :plantuml)

    expect(matches(svg, "//text[@font-family='monospace']").map(&:text))
      .to eq(["This position is ignored: TOP"])
  end

  it "drops the note of the note-top-on-ref case" do
    svg = Sirena.render(source_of("1f75ab64bf5e"), notation: :plantuml)

    expect(matches(svg, "//text[.='x']")).to be_empty
  end

  it "draws a bar for each call of the autoactivate case" do
    svg = Sirena.render(source_of("e6d99fb6ac3c"), notation: :plantuml)
    bare = source_of("e6d99fb6ac3c").sub(/^autoactivate on\n/, "")

    plain = Sirena.render(bare, notation: :plantuml)

    expect(rect_count(svg) - rect_count(plain)).to eq(3)
  end

  it "draws the head labels of the Roboto case in its font" do
    svg = Sirena.render(source_of("a13609de5404"), notation: :plantuml)
    labels = matches(svg, "//text[@font-family='Roboto'][@font-weight='900']")

    expect(labels.size).to eq(4)
  end

  it "draws the heads of the Roboto case in its line colour" do
    svg = Sirena.render(source_of("a13609de5404"), notation: :plantuml)

    expect(matches(svg, "//rect[@stroke='#EE0000']").size).to eq(4)
  end

  it "draws a coloured arrow's shaft and head in its colour" do
    source = "@startuml\nparticipant A\nA -[#22A722]> B\n@enduml"
    svg = Sirena.render(source, notation: :plantuml)
    strokes = matches(svg, "//g[@id='message-1']/*/@stroke").map(&:value)

    expect(strokes.uniq).to eq(["#22A722"])
  end

  it "wraps the long messages of the leftmsg case" do
    svg = Sirena.render(source_of("990470abe6d9"), notation: :plantuml)

    expect(matches(svg, "//g[@id='message-1']/text").size).to be > 3
  end

  it "draws no fill for the transparent heads of the alpha case" do
    svg = Sirena.render(source_of("1f8e5fb51e4d"), notation: :plantuml)
    heads = matches(svg, "//rect[@height='36.0'][@fill='none']")

    expect(heads.size).to eq(8)
  end

  it "keeps the opacity of the translucent heads of the alpha case" do
    svg = Sirena.render(source_of("1f8e5fb51e4d"), notation: :plantuml)

    expect(matches(svg, "//rect/@fill-opacity").map(&:value).uniq)
      .to eq(%w[0.00392 0.99608])
  end

  it "refuses every other case instead of rendering part of it" do
    refused = unread_cases.map { |name| refusal(name) }

    expect(refused).to all(be_a(StandardError))
  end
end
