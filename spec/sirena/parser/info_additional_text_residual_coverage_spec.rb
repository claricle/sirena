# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/info"

RSpec.describe Sirena::Parser::Info do
  it "ignores additional header text without enabling showInfo" do
    diagram = described_class.new.parse("info ignored words")

    expect([diagram.class, diagram.show_info, diagram.valid?])
      .to eq([Sirena::Diagram::Info, false, true])
  end
end
