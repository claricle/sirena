# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render C4 validity" do
    it "preserves the legacy empty C4 diagram header" do
      expect(described_class.render("C4 diagram\n")).to start_with("<svg")
    end

    it "renders a canonical diagram with a labelled element" do
      source = "C4Context\nPerson(customerA, \"Customer\")\n"

      expect(described_class.render(source)).to include(">Customer</text>")
    end

    ["C4Context", "C4Context;"].each do |header|
      it "rejects an empty #{header} diagram" do
        expect { described_class.render("#{header}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    [
      ["Person", "$link", '$link="https://github.com/mermaidjs"'],
      ["Person_Ext", "$link", '$link="https://github.com/mermaidjs"'],
      ["Person", "$sprite", '$sprite="users"'],
      ["Person_Ext", "$sprite", '$sprite="users"'],
      ["Person", "$tags", '$tags="tag1,tag2"'],
      ["Person_Ext", "$tags", '$tags="tag1,tag2"'],
    ].each do |type, name, attribute|
      it "rejects #{type} with #{name} in the required label position" do
        source = "C4Context\n#{type}(customerA, #{attribute})\n"

        expect { described_class.render(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end
end
