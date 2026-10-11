# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  subject(:tasks) { scene.sections.flat_map(&:tasks) }

  let(:source) do
    File.read("spec/mermaid/gantt/click_security_loose-0d2cc455.mmd")
  end
  let(:scene) { described_class.new.call(Sirena::Parser::Gantt.new.parse(source)) }

  it "snaps task bars to the oracle's integer pixel grid" do
    bars = tasks.to_h { |task| [task.label.text, task.bar] }

    expect([bars.fetch("Completed task").width,
            bars.fetch("Active task").x,
            bars.fetch("Add to mermaid").width]).to eq([75.0, 312.0, 38.0])
  end

  it "centres ticks on the oracle's half-pixel grid" do
    positions = scene.timeline.labels.values_at(0, -1).map(&:x)

    expect(positions).to eq([237.5, 834.5])
  end
end
