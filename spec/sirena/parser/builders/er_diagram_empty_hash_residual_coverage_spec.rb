# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::ErDiagram do
  it "builds an empty diagram from a header-only hash" do
    diagram = described_class.new.apply({ header: "erDiagram" })

    expect([diagram.entities, diagram.relationships, diagram.direction])
      .to eq([[], [], nil])
  end
end
