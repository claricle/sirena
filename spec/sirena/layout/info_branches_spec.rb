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

  it "ignores the injected font size: mmdc fixes the version at 32" do
    expect(label_for({ show_info: true }, 21)).to have_attributes(
      text: "v11.12.0", font_size: 32.0, x: 100.0, y: 40.0,
    )
  end

  it "keeps the same label for a nonpositive injected font size" do
    expect(label_for({}, 0)).to have_attributes(text: "v11.12.0",
                                                font_size: 32.0)
  end
end
