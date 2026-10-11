# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  let(:case_ids) do
    %w[
      should_handle_multiline_notes_with_different_lin-90d75e03
      should_handle_multiline_notes_with_different_lin-b6ac271b
      statediagram_spec-1acdbd7b
      statediagram_spec-3fdaec54
      statediagram_spec-ae578725
      statediagram_spec-bdd17264
      statediagram_v2_spec-330443ed
      statediagram_v2_spec-6aad18a9
      statediagram_v2_spec-9dfc4ef4
    ]
  end
  let(:parser) { Sirena::Parser::StateDiagram.new }
  let(:layout) { described_class.new }

  it "matches the pinned multiline attached-note dimensions" do
    dimensions = case_ids.to_h do |case_id|
      source = File.read("spec/mermaid/state_diagram/#{case_id}.mmd")
      scene = layout.scene(parser.parse(source))
      note = scene.children.find { |node| node.id == "State1----note" }

      [case_id, [note.width, note.height]]
    end

    expect(dimensions.values.uniq).to eq([[68.53125, 150.0]])
  end
end
