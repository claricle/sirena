# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Activity::Text do
  it "leaves a math formula's tags for Creole to draw as monospace" do
    expect(described_class.clean("a <math>x^2+y_1</math> b", line: 1))
      .to eq("a <math>x^2+y_1</math> b")
  end

  it "leaves a latex formula the same way" do
    expect(described_class.clean("<latex>a_b</latex>", line: 1))
      .to eq("<latex>a_b</latex>")
  end
end
