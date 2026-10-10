# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Radar do
  it "ignores an unsupported statement type" do
    result = described_class.build([{ type: :future_statement }])

    expect(result).to eq(
      title: nil, acc_title: nil, acc_descr: nil,
      axes: [], curves: [], options: {}
    )
  end
end
