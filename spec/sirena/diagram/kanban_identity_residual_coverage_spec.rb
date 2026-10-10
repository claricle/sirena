# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/kanban"

RSpec.describe Sirena::Diagram::Kanban do
  it("identifies itself as kanban") do
    expect(described_class.new.diagram_type).to eq(:kanban)
  end
end
