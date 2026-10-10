# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::C4 do
  subject(:builder) { described_class.new }

  it "returns an empty diagram for unsupported top-level input" do
    diagram = builder.apply("invalid")

    expect(diagram).to have_attributes(
      elements: [], boundaries: [], relationships: [],
    )
  end

  it "uses an empty layout config for unsupported config input" do
    diagram = builder.apply([{ config_params: "invalid" }])

    expect(diagram.layout_config).to eq("")
  end
end
