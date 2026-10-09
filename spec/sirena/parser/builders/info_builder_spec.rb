# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Info do
  subject(:diagram) { described_class.new.apply(tree) }

  {
    "an inline flag in an array" => [[{ show_info_inline: "showInfo" }], true],
    "a body flag in an array" => [[{ show_info_body: "showInfo" }], true],
    "a blank inline flag" => [[{ show_info_inline: "  " }], false],
    "a blank body flag" => [[{ show_info_body: " " }], false],
    "a nil body flag" => [[{ show_info_body: nil }], false],
    "a nil inline flag" => [[{ show_info_inline: nil }], false],
    "noise in an array" => [["noise"], false],
    "an inline flag in a hash" => [{ show_info_inline: "showInfo" }, true],
    "a body flag in a hash" => [{ show_info_body: "showInfo" }, true],
    "an empty hash" => [{}, false],
    "a non-tree value" => ["junk", false],
  }.each do |name, (tree, expected)|
    context "with #{name}" do
      let(:tree) { tree }

      it "sets show_info to #{expected}" do
        expect(diagram.show_info).to eq(expected)
      end
    end
  end
end
