# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::ShapeStyles do
  let(:source) do
    File.expand_path("../../../lib/sirena/theme/shape_styles.rb", __dir__)
  end
  let(:styles) do
    Sirena::Theme.const_get(:ShapeStyles).from_yaml("stroke_width: 2.5")
  end

  before do
    stub_const("Sirena::Theme", Class.new)
    load source
  end

  it("loads and maps YAML after Theme exists") do
    expect(styles.stroke_width).to eq(2.5)
  end
end
