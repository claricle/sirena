# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  let(:plain) { laid_out("A -> B") }

  def shift_for(*lines)
    first_arrow_y(laid_out(*lines, "A -> B")) - first_arrow_y(plain)
  end

  def growth_for(*lines)
    laid_out(*lines, "A -> B").height - plain.height
  end

  it "pushes the rows down by a header's room" do
    expect(shift_for("header H")).to be_within(0.01).of(12.78)
  end

  it "adds a line of header room per line" do
    expect(shift_for("header", "H", "I", "end header"))
      .to be_within(0.01).of(24.56)
  end

  it "pushes the rows down by a two-line title" do
    expect(shift_for("title", "T", "U", "end title"))
      .to be_within(0.01).of(53.98)
  end

  it "does not push the rows down for a footer" do
    expect(shift_for("footer F")).to eq(0)
  end

  it "grows the page by a footer's room" do
    expect(growth_for("footer F")).to be_within(0.01).of(12.78)
  end

  it "grows the page by a caption's room" do
    expect(growth_for("caption C")).to be_within(0.01).of(19.49)
  end

  it "grows the page by a legend's room" do
    expect(growth_for("legend K")).to be_within(0.01).of(51.49)
  end

  it "grows the page by a taller legend's extra line" do
    expect(growth_for("legend", "K", "L", "end legend"))
      .to be_within(0.01).of(67.98)
  end

  it "pushes the rows down for a legend at the top" do
    expect(shift_for("legend top", "K", "end legend"))
      .to be_within(0.01).of(51.49)
  end

  it "does not grow the page twice for a legend at the top" do
    expect(growth_for("legend top", "K", "end legend"))
      .to be_within(0.01).of(51.49)
  end
end
