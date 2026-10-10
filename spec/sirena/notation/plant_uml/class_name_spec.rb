# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/class_name"

RSpec.describe Sirena::Notation::PlantUML::ClassName do
  {
    "Plain" => ["Plain"],
    "pkg.Cls" => ["Cls"],
    "a.b\\nc.d" => ["d"],
    "A\\nB" => %w[A B],
    "A\\rB" => %w[A B],
    "A\\lB" => %w[A B],
    "A\\r\\nB" => ["A", " ", "B"],
    "A\\n" => ["A", " "],
    "A\\tB" => ["A    B"],
    "A\\\\B" => ["A\\B"],
    "A\\\\nB" => ["A\\nB"],
    "A\\qB" => ["A\\qB"],
    " A " => ["A"],
  }.each do |name, lines|
    it "draws #{name.inspect} as #{lines.inspect}" do
      expect(described_class.lines(name)).to eq(lines)
    end
  end

  it "names the namespaces before the last dot" do
    expect(described_class.namespaces("a.b.C")).to eq(%w[a b])
  end

  it "finds a unicode escape" do
    expect(described_class.escapes?("A\\u0041")).to be(true)
  end

  it "does not find one in a plain name" do
    expect(described_class.escapes?("A\\nB")).to be(false)
  end
end
