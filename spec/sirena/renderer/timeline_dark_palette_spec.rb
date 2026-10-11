# frozen_string_literal: true

require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::Timeline do
  let(:fills) do
    %w[#3794ff #4ec9b0 #f48771 #dcdcaa #89d185 #9cdcfe #fbbf24
       #858585 #969696 #505050 #3e3e42 #404040]
  end
  let(:foregrounds) do
    Array.new(9, "#1e1e1e") + Array.new(3, "#d4d4d4")
  end
  let(:source) do
    sections = 12.times.flat_map do |index|
      ["  section section #{index}", "  task #{index}"]
    end
    (["timeline"] + sections).join("\n")
  end
  let(:triples) do
    document = REXML::Document.new(Sirena.render(source, theme: :dark))
    REXML::XPath.match(document, "//g[@class='timeline-node']").map do |node|
      [node.elements["g/path"].attributes["fill"],
       node.elements["text"].attributes["fill"],
       node.elements["g/line"].attributes["stroke"]]
    end
  end
  let(:expected) { fills.zip(foregrounds, foregrounds) }

  it "uses each dark fill, text, and rule triple for its section" do
    expect(triples.each_slice(2).map(&:uniq))
      .to eq(expected.zip)
  end

  it "keeps every text and rule pairing legible against its fill" do
    contrasts = expected.flat_map do |fill, text, rule|
      [contrast(fill, text), contrast(fill, rule)]
    end

    expect(contrasts).to all(be >= 4.5)
  end

  def contrast(left, right)
    high, low = [luminance(left), luminance(right)].sort.reverse
    (high + 0.05) / (low + 0.05)
  end

  def luminance(hex)
    channels = hex.delete_prefix("#").scan(/../).map do |pair|
      value = pair.to_i(16) / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    channels.zip([0.2126, 0.7152, 0.0722]).sum { |value, weight| value * weight }
  end
end
