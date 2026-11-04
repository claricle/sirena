# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (pie)" do
  it_behaves_like "native corpus parity", "pie"

  it_behaves_like "native edge parity", "pie", [
    "pie",
    "pie\n",
    "  pie  \n",
    "pie showData",
    "pie title Pets",
    "pie title: Pets",
    "pie showData title Pets  ",
    "pie title",
    "pie title:\n  \"a\" : 1",
    "pie\ntitle   T  \n\"a\" : 1",
    "pie\ntitle\n",
    "pie\r\n  \"a\" : 1\r\n  \"b\" : 2\r\n",
    "pie\n  'a' : 1\n  \"b\\\"c\" : 2.5",
    "pie\n  \"\" : 1",
    "pie\n  \"é ü 日本\" : 3",
    "pie\n  \"a\" : -1",
    "pie\n  \"a\" : 5.",
    "pie\n  \"a\" : .5",
    "pie\n  \"a\" : 1e3",
    "pie\n  \"a\" : 1 %% trailing\n  \"b\" : 2;",
    "pie\n%% comment\n  \"a\" : 1\n%% another",
    "pie\n  accTitle: Acc\n  accDescr: Desc\n  \"a\" : 1",
    "pie\n  accTitle:\n  \"a\" : 1",
    "pie\n  accDescr {\n   multi\n   line\n  }\n  \"a\" : 1",
    "pie\n  accDescr {\n  }\n",
    "pie\n  accDescr {\n unterminated",
    "pie\n  \"a\" 1",
    "pie\n  a : 1",
    "pie chart\n  \"a\" : 1",
    "Pie\n  \"a\" : 1",
    "pie\n  \"a\" : 1\n  \"a\" : 2",
    "%% lead\npie\n  \"a\" : 1",
    "",
    "   ",
  ]
end
