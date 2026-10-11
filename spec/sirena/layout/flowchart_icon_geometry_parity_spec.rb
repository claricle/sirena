# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::Flowchart.new }
  let(:source) do
    File.read(
      "spec/mermaid/flowchart/configuration_spec-5b7a1b25.mmd",
    )
  end

  it "reserves one icon advance while retaining the displayed label" do
    car = scene.children.find { |node| node.id == "F" }

    expect([
      car.labels.first.text,
      car.labels.first.width.round(3),
      car.width.round(3),
      car.height,
    ]).to eq(["Car", 44.992, 104.992, 54.0])
  end
end
