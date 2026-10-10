# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/info"

RSpec.describe Sirena::Layout::Info do
  def theme_with_size(size)
    typography = Struct.new(:font_size_base).new(size)
    instance_double(Sirena::Theme, typography: typography)
  end

  def label_for(graph, size)
    described_class.from_graph(graph, theme: theme_with_size(size)).label
  end

  it "uses a positive injected font size" do
    expect(label_for({ show_info: true }, 21)).to have_attributes(
      text: "Info: showInfo enabled", font_size: 21.0,
    )
  end

  it "falls back for a nonpositive injected font size" do
    expect(label_for({}, 0)).to have_attributes(text: "Info", font_size: 16.0)
  end
end
