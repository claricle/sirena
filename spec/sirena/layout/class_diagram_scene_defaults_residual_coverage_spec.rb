# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram::Scene do
  it "provides independent empty note and namespace collections" do
    first = described_class.new
    second = described_class.new

    expect(
      [first.notes, first.namespaces,
       first.notes.equal?(second.notes),
       first.namespaces.equal?(second.namespaces)],
    ).to eq([[], [], false, false])
  end
end
