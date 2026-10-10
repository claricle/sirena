# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::SpacingConfig do
  let(:source) do
    File.expand_path("../../../lib/sirena/theme/spacing_config.rb", __dir__)
  end
  let(:spacing) do
    Sirena::Theme.const_get(:SpacingConfig).from_yaml("node_margin: 12.5")
  end

  before do
    stub_const("Sirena::Theme", Class.new)
    load source
  end

  it "loads and maps YAML after Theme exists" do
    expect(spacing.node_margin).to eq(12.5)
  end
end
