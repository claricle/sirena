# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Renderer::StateDiagram do
  subject(:default_xml) { described_class.new.render(scene).to_xml }

  let(:source) do
    <<~MERMAID
      stateDiagram-v2
      [*] --> Idle
      Idle --> Choice: decide
      state Choice <<choice>>
      Choice --> Fork
      state Fork <<fork>>
      Fork --> Done
      Done --> [*]
    MERMAID
  end
  let(:diagram) { Sirena::Parser::StateDiagram.new.parse(source) }
  let(:scene) { Sirena::Layout::StateDiagram.new.call(diagram) }
  let(:dark) { Sirena::Theme::Registry.get(:dark) }
  let(:dark_xml) { described_class.new(theme: dark).render(scene).to_xml }

  def theme_colors(theme)
    %i[node_fill node_stroke edge_stroke label_text].map do |role|
      theme.colors.public_send(role)
    end
  end

  it "keeps the default themed rendering byte-identical" do
    expect(Digest::SHA256.hexdigest(default_xml)).to eq(
      "6b87128768df03e9615d479a41fc8281b87aa792db77c35ba35564471abef617",
    )
  end

  it "uses the dark theme for states, transitions, and labels" do
    expect(dark_xml).to include(*theme_colors(dark))
      .and(satisfy { |xml| xml != default_xml })
  end
end
