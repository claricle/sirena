# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/builders/pie"

RSpec.describe Sirena::Parser::Builders::Pie do
  let(:tree) do
    [
      { show_data: "showData" },
      { acc_title: "Revenue share" },
      { acc_descr: "Revenue grouped by product" },
    ]
  end
  let(:diagram) { described_class.new.apply(tree) }

  it "applies display and accessibility metadata" do
    expect([diagram.show_data, diagram.acc_title, diagram.acc_description])
      .to eq([true, "Revenue share", "Revenue grouped by product"])
  end
end
