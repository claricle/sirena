# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/treemap"

RSpec.describe Sirena::Diagram::TreemapNode do
  it "totals zero for a node with neither value nor children" do
    expect(described_class.new("empty").total_value).to eq(0.0)
  end
end
