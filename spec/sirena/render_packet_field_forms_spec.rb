# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render packet field forms" do
    it "renders a single-bit field" do
      svg = described_class.render("packet-beta\n  0: \"Flag\"\n")

      expect(svg).to include('width="27.0"', ">Flag</text>")
    end

    it "renders an escaped quote inside a field label" do
      svg = described_class.render("packet-beta\n  0-7: \"Say \\\"hi\\\"\"\n")

      expect(svg).to include('>Say "hi"</text>')
    end

    it "rejects a range whose end precedes its start" do
      source = "packet-beta\n  7-0: \"Reverse\"\n"

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError, /end.*greater.*start/i)
    end

    it "rejects a noncontiguous first field" do
      source = "packet-beta\n  8-15: \"Second byte\"\n"

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError, /start from 0/i)
    end
  end
end
