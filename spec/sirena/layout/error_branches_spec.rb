# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/error"

RSpec.describe Sirena::Layout::Error do
  def theme_with_size(size)
    typography = Struct.new(:font_size_base).new(size)
    instance_double(Sirena::Theme, typography: typography)
  end

  def label_for(graph, theme)
    described_class.from_graph(graph, theme: theme).label
  end

  it "uses a positive injected font size" do
    scene = described_class.from_graph(
      { message: "Failure" }, theme: theme_with_size(23)
    )
    expect(scene.label).to have_attributes(text: "Failure", font_size: 23.0)
  end

  it "falls back when the injected theme has no typography contract" do
    label = label_for({ message: "Failure" }, Object.new)

    expect(label.font_size).to eq(16.0)
  end
end
