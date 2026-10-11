# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::ClassDiagram do
  it "ignores a scalar extraction artifact" do
    diagram = described_class.new.apply("artifact", "")

    expect([diagram.entities, diagram.direction]).to eq([[], nil])
  end

  it "names a class by its id when the explicit label is empty" do
    diagram = Sirena::Parser::ClassDiagram.new.parse(
      "classDiagram\nclass A[\"\"]\n",
    )

    expect(diagram.entities.map { |entity| [entity.id, entity.name] })
      .to eq([%w[A A]])
  end
end
