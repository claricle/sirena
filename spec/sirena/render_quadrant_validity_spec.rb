# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render quadrant validity" do
    it "refuses a classDef style Mermaid does not support" do
      source = "quadrantChart\nclassDef c fill:#ff0000\nA:::c: [0.5, 0.5]\n"

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError, /style named fill/)
    end

    it "refuses an unsupported style among supported ones" do
      source = "quadrantChart\nclassDef c radius: 5, fill:#f00\n"

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError, /style named fill/)
    end

    it "renders a classDef using only supported styles" do
      source = "quadrantChart\nclassDef c color: #ff0000, radius: 8\n" \
               "Alpha:::c: [0.4, 0.6]\n"

      expect(described_class.render(source)).to include(">Alpha</text>")
    end
  end
end
