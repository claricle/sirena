# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Timeline do
  include TimelineRenderHelpers

  # Path data, wrapper classes and colours below are copied from the mmdc
  # references in spec/fixtures_mermaid/timeline (010, 002 and 007).
  let(:two_sections) do
    "timeline\n section a\n task1\n section b\n task2\n"
  end
  let(:doc) { render_doc(two_sections) }
  let(:wrapped) do
    render_doc("timeline\n title Release\n 2020 : Machinery, Water " \
               "power, Steam <br>power\n")
  end

  it "wraps a period in a taskWrapper group" do
    expect(attrs(doc, "//g[@class='taskWrapper']", "transform"))
      .to eq(["translate(100, 167.8)", "translate(300, 167.8)"])
  end

  it "wraps an event in an eventWrapper group" do
    expect(nodes(wrapped, "//g[@class='eventWrapper']").length).to eq(1)
  end

  it "draws a card as mmdc's rounded-top path" do
    expect(attrs(doc, "//path[@class='node-bkg']", "d").first)
      .to eq("M0 62.8 v-57.8 q0,-5 5,-5 h180 q5,0 5,5 v62.8 H0 Z")
  end

  it "draws the rule under a card, full width" do
    expect(attrs(doc, "//line[@class='node-line']", "x2").first.to_f)
      .to eq(190)
  end

  it "fills the first section with the first palette entry" do
    expect(attrs(doc, "//path[@class='node-bkg']", "fill").first)
      .to eq("#8686ff")
  end

  it "fills the second section with the second palette entry" do
    expect(attrs(doc, "//path[@class='node-bkg']", "fill").last)
      .to eq("#ffff78")
  end

  it "colours text white on the first section, black on the second" do
    expect(attrs(doc, "//text", "fill"))
      .to eq(%w[#ffffff #ffffff #000000 #000000])
  end

  it "draws the drop line dashed" do
    expect(attrs(doc, "//path[@stroke-dasharray]", "stroke-dasharray")
      .uniq).to eq(["5,5"])
  end

  it "draws the base arrow with an arrowhead and no dash" do
    arrow = nodes(doc, "//g[@class='lineWrapper']/path").last

    expect(arrow.attributes["stroke-dasharray"]).to be_nil
  end

  it "splits wrapped text into one tspan per line" do
    expect(nodes(wrapped, "//tspan").map(&:text)).to eq(
      ["Machinery, Water", "power, Steam", "power"],
    )
  end

  it "draws the title bold" do
    expect(attrs(wrapped, "//text[@font-weight]", "font-weight"))
      .to eq(["bold"])
  end

  it "renders the scene's canvas verbatim" do
    scene = lay_out(two_sections)
    svg = described_class.new.render(scene)

    expect(svg.view_box).to eq(scene.view_box)
  end

  it "does not retain positional state between renders" do
    scene = lay_out(two_sections)
    renderer = described_class.new
    first = renderer.render(scene).to_xml

    expect(renderer.render(scene).to_xml).to eq(first)
  end
end
