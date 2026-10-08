# frozen_string_literal: true

require "spec_helper"

module KanbanMetadataScalarHelpers
  def parse_card(key, text)
    source = "kanban\n  col[C]\n    k[K]@{ #{key}: #{text} }\n"
    parser.parse(source).columns.first.cards.first
  end

  def parse_column(text)
    parser.parse("kanban\n  col[C]@{ label: #{text} }\n").columns.first
  end
end

# Mermaid resolves each unquoted `@{ }` value with js-yaml and then calls
# `.toString()` on the result, so a number is drawn the way JavaScript
# prints it. Every row of `printed` and `verbatim` was driven through
# mmdc 11.12.0 (bundled mermaid 11.16.1) as a ticket, an assigned and a
# column label, and read off the SVG text.
RSpec.describe Sirena::Parser::Kanban do
  include KanbanMetadataScalarHelpers

  let(:parser) { described_class.new }
  let(:printed) do
    {
      "1e0" => "1", "-1e0" => "-1", "1E3" => "1000", "1e+3" => "1000",
      "2.5e-3" => "0.0025", "0.1e1" => "1", "1.50" => "1.5", "3.0" => "3",
      ".5" => "0.5", "5." => "5", "+1" => "1", "007" => "7", "1_0" => "10",
      "0x10" => "16", "0o17" => "15", "0b11" => "3",
      "1e-7" => "1e-7", "1e21" => "1e+21", "1e23" => "1e+23",
      "12345678901234567890" => "12345678901234567000",
      ".inf" => "Infinity", "-.inf" => "-Infinity",
      "True" => "true", "TRUE" => "true"
    }
  end
  let(:verbatim) do
    {
      "'1e0'" => "1e0", '"0x10"' => "0x10", "1e0x" => "1e0x",
      "1.2.3" => "1.2.3", "1_" => "1_", "1e" => "1e", "MC-1" => "MC-1",
      "0X10" => "0X10", "-.5" => "-.5", "+.5" => "+.5"
    }
  end

  describe "#parse metadata scalars" do
    it "prints an unquoted ticket the way mermaid prints the resolved scalar" do
      actual = printed.keys.to_h do |text|
        [text, parse_card("ticket", text).ticket]
      end

      expect(actual).to eq(printed)
    end

    it "prints an unquoted assigned the same way" do
      actual = printed.keys.to_h do |text|
        [text, parse_card("assigned", text).assigned]
      end

      expect(actual).to eq(printed)
    end

    it "prints an unquoted column label the same way" do
      actual = printed.keys.to_h { |text| [text, parse_column(text).title] }

      expect(actual).to eq(printed)
    end

    # Passes without the fix; keep it. It goes red if the coercion ever
    # reaches a quoted value or a string js-yaml leaves alone.
    it "keeps a string js-yaml leaves alone, and a quoted one, as written" do
      actual = verbatim.keys.to_h do |text|
        [text, parse_card("ticket", text).ticket]
      end

      expect(actual).to eq(verbatim)
    end

    # Passes without the fix; keep it. It goes red if an empty quoted value
    # stops being dropped.
    it "drops an empty quoted value, which mermaid treats as unset" do
      expect(parse_card("ticket", "''").ticket).to be_nil
    end

    # Mermaid rejects a repeated key, so a later value that resolves to a
    # dropped one must not make it look like a single entry. It goes red if
    # that repeat is accepted again.
    it "refuses a repeated key whose later value resolves to a dropped one" do
      expect { parse_card("ticket", "A, ticket: 0") }
        .to raise_error(Sirena::Parser::ParseError, /Duplicate key: ticket/)
    end

    # Passes without the fix; keep it. Bracket text is not a metadata scalar
    # and mermaid does not coerce it. It goes red if the coercion is ever
    # applied to the bracket text.
    it "leaves the bracket text alone, which mermaid draws as written" do
      column = parser.parse("kanban\n  c[1e0]\n    k[0x10]\n").columns.first

      expect([column.title, column.cards.first.text]).to eq(%w[1e0 0x10])
    end
  end
end
