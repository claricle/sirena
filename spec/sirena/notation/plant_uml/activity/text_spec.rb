# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Activity::Text do
  it "keeps a math formula as its source with the tags removed" do
    expect(described_class.clean("a <math>x^2+y_1</math> b", line: 1))
      .to eq("a x^2+y_1 b")
  end

  it "keeps a latex formula the same way" do
    expect(described_class.clean("<latex>a_b</latex>", line: 1))
      .to eq("a_b")
  end
end
