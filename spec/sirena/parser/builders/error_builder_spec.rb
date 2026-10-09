# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Error do
  subject(:diagram) { described_class.new.apply(tree) }

  {
    "a string message in an array" => [[{ message: " boom " }], "boom"],
    "a hash message" => [[{ message: { text: " bang " } }], "bang"],
    "a non-string message" => [[{ message: 7 }], "7"],
    "a blank message" => [[{ message: "  " }], nil],
    "a nil message" => [[{ message: nil }], nil],
    "noise in an array" => [["noise", { other: 1 }], nil],
    "a hash tree" => [{ message: "x" }, "x"],
    "a hash tree without a message" => [{ other: 1 }, nil],
  }.each do |name, (tree, expected)|
    context "with #{name}" do
      let(:tree) { tree }

      it "sets the message to #{expected.inspect}" do
        expect(diagram.message).to eq(expected)
      end
    end
  end
end
