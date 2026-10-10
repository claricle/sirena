# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Pie do
  subject(:diagram) { described_class.new.apply(tree) }

  context "with a hash tree without statements" do
    let(:tree) { { title: "Only" } }

    it "reads just the top-level fields" do
      expect([diagram.title, diagram.show_data,
              diagram.slices]).to eq(["Only", false, []])
    end
  end

  context "with an array tree" do
    let(:tree) do
      [{ title: nil }, { title: "   " },
       { title: { other: "plain" } }, { show_data: nil },
       { data_entry: true, label: "X", value: "3" },
       { standalone_title: "Late" }]
    end

    it "skips blank titles and absent flags", :aggregate_failures do
      expect(diagram.title).to eq("Late")
      expect(diagram.show_data).to be(false)
      expect(diagram.slices.map(&:label)).to eq(["X"])
    end
  end

  context "with a title hash holding a string, and a non-string title" do
    it "unwraps string hashes" do
      tree = [{ standalone_title: { string: "S" } }]
      expect(described_class.new.apply(tree).title).to eq("S")
    end

    it "stringifies other values" do
      expect(described_class.new.apply([{ title: 12 }]).title).to eq("12")
    end
  end
end
