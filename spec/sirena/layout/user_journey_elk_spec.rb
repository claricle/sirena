# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::UserJourney do
  let(:source) do
    <<~MERMAID
      journey
        title Checkout
        section Find
          This is a deliberately long discovery step: 5: Buyer
          Pay: 2: Buyer, Bank
    MERMAID
  end

  let(:diagram) { Sirena::Parser::UserJourney.new.parse(source) }
  let(:layout) { described_class.new }
  let(:elk_scene) do
    layout.placement = :elk
    layout.call(diagram)
  end

  it "renders through the public API with real ELK placement" do
    svg = Sirena.render(source, layout_engine: :elk)

    expect(svg).to include('id="task-task_0"', 'id="task-task_1"')
  end

  it "publishes ELK task positions and variable dimensions to the Scene" do
    first, second = elk_scene.tasks.map(&:box)

    expect([first.width > 150, first.height, second.x - first.x, second.y])
      .to eq([true, 80.0, first.width + 60, 110.0])
  end

  it "raises the ELK error without falling back" do
    allow(Elkrb).to receive(:layout).and_raise(Elkrb::Error, "seeded journey")

    expect { Sirena.render(source, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /seeded journey/)
  end

  it "renders an empty valid journey through ELK" do
    svg = Sirena.render("journey\n", layout_engine: :elk)

    expect([svg.start_with?("<svg"), svg.include?('id="task-')])
      .to eq([true, false])
  end

  it "preserves default rendering byte for byte" do
    digest = Digest::SHA256.hexdigest(Sirena.render(source))

    expect(digest)
      .to eq("83b328cc01b68da58fcee08a737530e5a3aaf472837cb65a8d0a90e9bf25aed1")
  end
end
