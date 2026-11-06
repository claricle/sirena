# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Timing::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:clocks) do
    <<~PUML
      @startuml
      clock "C0" as C0 with period 50
      binary "B" as B
      @0
      B is low
      @100
      B is high
      @300
      B is low
      @enduml
    PUML
  end

  def render(source)
    Sirena::Engine.new.render(source, notation: :plantuml)
  end

  def texts(svg)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  def grid_gaps(svg)
    xs = svg.scan(/<line[^>]*stroke-dasharray="3,5"[^>]*>/)
      .map { |l| l[/x1="([\d.]+)"/, 1].to_f }.sort
    xs.each_cons(2).map { |a, b| b - a }
  end

  it "grids every common step, 50 pixels apart", :aggregate_failures do
    gaps = grid_gaps(render(clocks))

    expect(gaps.size).to eq(7)
    expect(gaps.uniq).to eq([50.0])
  end

  it "labels only the named times", :aggregate_failures do
    labels = texts(render(clocks))

    expect(labels).to include("0", "50", "100", "300")
    expect(labels).not_to include("150", "200", "250", "350")
  end

  it "steps by the scale unit and labels every dated tick" do
    svg = render("@startuml\nconcise \"S\" as S\nscale 2592000 as 50 pixels\n" \
                 "@2000/11/01\nS is \"W\"\n@2001/02/01\nS is \"Sp\"\n@enduml\n")

    expect(texts(svg)).to include("11/01", "12/01", "12/31", "01/30")
  end

  it "falls back to the times themselves when no whole step exists" do
    svg = render("@startuml\nconcise \"S\" as S\n@0.5\nS is a\n" \
                 "@1.25\nS is b\n@enduml\n")

    expect(texts(svg)).to include("0.5", "1.25")
  end

  it "draws a slanted tab under each lane name" do
    slants = render(clocks).scan(/<line\s+stroke="\#333333"[^>]*y1="([\d.]+)"
                                  [^>]*y2="([\d.]+)"/x)
      .count { |from, to| from.to_f > to.to_f }

    expect(slants).to eq(2)
  end
end
