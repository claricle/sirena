# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Requirement do
  subject(:widths) do
    sources.to_h do |case_id|
      source = File.read("spec/mermaid/requirement/#{case_id}.mmd")
      diagram = Sirena::Parser::Requirement.new.parse(source)
      scene = described_class.new.call(diagram)
      [case_id, scene.children.to_h { |node| [node.id, node.width] }]
    end
  end

  let(:sources) do
    %w[
      requirement-9f8b7e75
      will_use_a_accessibility_title_and_description_a-3638a406
    ]
  end

  it "matches Mermaid's browser-sized requirement and element widths" do
    expect(widths).to eq(
      sources[0] => { "test_req" => 157.734375,
                      "test_entity" => 138.09375 },
      sources[1] => { "test_name" => 142.28125 },
    )
  end
end
