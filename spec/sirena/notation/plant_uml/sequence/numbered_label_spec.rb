# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::NumberedLabel do
  subject(:label) { described_class.new(->(text) { text.size * 10.0 }) }

  let(:sequence) { Sirena::Notation::PlantUML::Sequence }
  let(:message) do
    sequence::Message.new(from: "A", to: "B", label: "hello",
                          style: sequence::ArrowStyle.plain(:filled),
                          number: 12)
  end

  it "adds the width of the number and a gap of four" do
    expect(label.extra(message)).to eq(24.0)
  end

  it "adds nothing to a message with no number" do
    plain = message.numbered(nil)

    expect(label.extra(plain)).to eq(0.0)
  end

  it "puts the label one number and gap after the number" do
    number, text = label.texts(message, 100.0, 50.0, "start")

    expect([number.x, text.x]).to eq([100.0, 124.0])
  end

  it "centres the pair on x" do
    number, = label.texts(message, 100.0, 50.0, "middle")

    expect(number.x).to eq(100.0 - ((24.0 + 50.0) / 2))
  end

  it "ends the pair at x" do
    number, = label.texts(message, 100.0, 50.0, "end")

    expect(number.x).to eq(100.0 - 74.0)
  end

  it "draws the number in bold and the label as it is" do
    number, text = label.texts(message, 0.0, 0.0, "start")

    expect([number.weight, text.weight]).to eq(["bold", nil])
  end
end
