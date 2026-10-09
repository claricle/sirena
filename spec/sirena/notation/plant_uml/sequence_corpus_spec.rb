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

  it "draws a cross for a destroyed participant of a rendered case" do
    source = source_of("184d55bcfb9c")
    counts = [source, source.sub(/^destroy .*\n/, "")].map do |text|
      matches(Sirena.render(text, notation: :plantuml), "//line").size
    end

    expect(counts.first - counts.last).to eq(2)
  end

  it "fills the bar of a rendered case with its colour" do
    svg = Sirena.render(source_of("2dd4eecfa67b"), notation: :plantuml)
    fills = matches(svg, "//rect/@fill").map(&:value)

    expect(fills).to include("red", "green")
  end

  it "refuses every other case instead of rendering part of it" do
    refused = unread_cases.map { |name| refusal(name) }

    expect(refused).to all(be_a(StandardError))
  end
end
