# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::ElkPlacement do
  let(:source) do
    path = File.expand_path(
      "../../../examples/state_diagram/01-simple-states.mmd", __dir__
    )
    File.read(path)
  end

  let(:transition_ids) do
    %w[
      start_1_to_Idle Idle_to_Connecting Connecting_to_Connected
      Connecting_to_Error start_2_to_Authenticated Authenticated_to_Active
      start_3_to_Reading Reading_to_Writing Writing_to_Reading
      Reading_to_Processing Processing_to_Reading Active_to_Suspended
      Suspended_to_Active Connected_to_Disconnecting Error_to_Idle
      Disconnecting_to_Idle Suspended_to_Disconnecting Idle_to_end_4
    ].map { |id| "transition-#{id}" }
  end

  describe "State diagram cycles" do
    it "renders nested cycles and a cross-hierarchy transition" do
      svg = Sirena.render(source, layout_engine: :elk)
      document = REXML::Document.new(svg)
      rendered_ids = REXML::XPath.match(document, "//*[@id]").filter_map do |node|
        id = node.attributes["id"]
        id if id.start_with?("transition-")
      end

      expect([document.root.name, rendered_ids]).to eq(["svg", transition_ids])
    end
  end
end
