# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (packet)" do
  it_behaves_like "native corpus parity", "packet"

  it_behaves_like "native edge parity", "packet", [
    "packet-beta",
    "packet-beta\n",
    "packet-beta  \n",
    "  packet-beta",
    "packet",
    "Packet-beta",
    "packet-beta\n  title Hello",
    "packet-beta\n  title Hello\n",
    "packet-beta\n  title\n",
    "packet-beta\n  title  \n",
    "packet-beta\n  title A\n  title B\n",
    "packet-beta\r\n  title A\r\n  0-7: \"a\"\r\n",
    "packet-beta\n  0-7: \"a\"\n  8-15: \"b\"\n",
    "packet-beta\n  0-7: \"a\"\n  8-15: \"b\"",
    "packet-beta\n  0: \"a\"\n  1: \"b\"\n",
    "packet-beta\n  0:\"a\"\n",
    "packet-beta\n  0-7 \"a\"\n",
    "packet-beta\n  0-7: a\n",
    "packet-beta\n  0-7: \"\"\n",
    "packet-beta\n  0-7: \"a\\\"b\\\\c\"\n",
    "packet-beta\n  0-7: \"é ü 日本\"\n",
    "packet-beta\n  0-7: \"unterminated\n",
    "packet-beta\n  3-1: \"a\"\n",
    "packet-beta\n  1-7: \"a\"\n",
    "packet-beta\n  0-7: \"a\"\n  10-15: \"b\"\n",
    "packet-beta\n  0-7: \"a\"\n  4-9: \"b\"\n",
    "packet-beta\n%% comment\n\n  %% another\n",
    "packet-beta\n  0-7: \"a\" %% trailing\n",
    "packet-beta\n  \n\n  0-7: \"a\"\n  \n",
    "packet-beta\n  ",
    "packet-beta;\n  0: \"a\"",
    "packet-beta extra\n  0: \"a\"",
    "packet-beta\n\t0-7: \"a\"\n",
    "",
    "   ",
  ]
end
