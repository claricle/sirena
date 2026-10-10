# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram::Scene do
  let(:first) { described_class.new }
  let(:second) { described_class.new }
  let(:collections) do
    [first.notes, first.namespaces,
     first.notes.equal?(second.notes),
     first.namespaces.equal?(second.namespaces)]
  end

  it "provides independent empty note and namespace collections" do
    expect(collections).to eq([[], [], false, false])
  end
end
