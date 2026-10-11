# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Info, "#build_graph" do
  subject(:graph) { described_class.new.build_graph(data) }

  let(:data) do
    Sirena::IR::Data.new(id: "status", role: "information_panel")
  end

  it "defaults an omitted show-information value" do
    expect(graph.fetch(:show_info)).to be(false)
  end
end
