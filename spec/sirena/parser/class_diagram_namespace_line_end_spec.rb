# frozen_string_literal: true

require "spec_helper"

# `namespace Name { <statement> }` closes on the same line as its one
# statement with no newline before the `}` (spec/mermaid/class/159_*,
# class_diagram/035_*, 051_*, 132_* — all named "comment inside brackets"
# by the corpus extractor but actually this same-line-namespace shape).
RSpec.describe Sirena::Parser::ClassDiagram, "#parse namespace line endings" do
  let(:parser) { described_class.new }

  {
    "bodyless class declaration closes the namespace on the same line" =>
      ["namespace Namespace1 { class Class1 }", ["Namespace1.Class1"]],
    "bodyless class declaration with no space before the brace" =>
      ["namespace Namespace1b { class Class1}", ["Namespace1b.Class1"]],
    "the closing brace can instead follow a newline" =>
      ["namespace Namespace2 { class Class1\n}", ["Namespace2.Class1"]],
    "a class with a body still closes the namespace after its own brace" =>
      ["namespace Namespace3 {\nclass Class1 {\nint : test\n}\n}",
       ["Namespace3.Class1"]],
    "a bodied class closes the namespace on the same line with a space" =>
      ["namespace Namespace4 { class Class1 {} }", ["Namespace4.Class1"]],
    "a bodied class closes the namespace on the same line with no space" =>
      ["namespace Namespace5 { class Class1 {}}", ["Namespace5.Class1"]],
  }.each do |name, (statement, expected_ids)|
    it(name.to_s) do
      source = "classDiagram\n#{statement}\n"

      expect(parser.parse(source).entities.map(&:id)).to eq(expected_ids)
    end
  end

  # `class_declaration_end`'s new brace branch is `space? >> rbrace.present?`
  # -- it must only skip spaces before the `}`, not scan past anything else.
  # A widened version that scans past any character
  # (`(rbrace.absent? >> any).repeat >> rbrace.present?`) stays green
  # against every acceptance example above, since none of them puts a
  # non-space character between the class declaration and the brace. This
  # rejects the shape that mutant would wrongly accept; mmdc 11.12.0
  # rejects it too (parse error on the stray `#`, confirmed against a
  # local mmdc render).
  it "does not let anything but spaces stand between the declaration and the brace" do
    source = "classDiagram\nnamespace Namespace6 { class Class1 # }\n"

    expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
  end
end
