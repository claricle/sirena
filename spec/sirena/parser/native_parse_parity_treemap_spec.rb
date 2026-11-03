# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (treemap)" do
  it_behaves_like "native corpus parity", "treemap"

  it_behaves_like "native edge parity", "treemap", [
    "treemap",
    "treemap\n",
    "treemap-beta\n",
    "treemap  \n",
    "Treemap\n",
    "treemap-beta",
    "  treemap\n",
    "%% lead\ntreemap\n",
    "treemap\r\n\"A\": 1\r\n",
    "treemap\n\"A\"",
    "treemap\n\"A\": 1\n  \"B\": 2\n  \"C\": 3\n\"D\": 4",
    "treemap\n\"A\"\n  \"B\": 2\n    \"C\": 3\n  \"D\": 4\n\"E\"",
    "treemap\n  \"A\": 1\n\"B\": 2",
    "treemap\n\"A\" , 1.5\n\"B\" : -2",
    "treemap\n\"A\": 1.\n",
    "treemap\n\"A\": .5\n",
    "treemap\n\"A\":::cls\n\"B\": 1:::c-2",
    "treemap\n\"A\": 1 %% trailing\n",
    "treemap\n\"A\": 1   \n",
    "treemap\n\"\": 1\n",
    "treemap\n\"a\\\"b\": 1\n",
    "treemap\n\"é 日本\": 1\n",
    "treemap\n'single': 1\n",
    "treemap\nbare: 1\n",
    "treemap\n\"A\": x\n",
    "treemap\ntitle Hello\n\"A\": 1",
    "treemap\ntitle\n",
    "treemap\ntitle A\ntitle B\n",
    "treemap\n  title Indented\n",
    "treemap\naccTitle: Acc\naccDescr: Desc\n\"A\": 1",
    "treemap\naccDescr Desc\n",
    "treemap\naccTitle:\n",
    "treemap\nclassDef c fill:red;\n\"A\":::c",
    "treemap\nclassDef c fill:red,stroke:blue\n\"A\"",
    "treemap\nclassDef c fill:red;\n  stroke:blue;\n",
    "treemap\nclassDef\n",
    "treemap\n%% comment\n\n\"A\": 1\n%% end",
    "treemap\n\t\"A\": 1\n",
    "treemap\n\"A\": 1\n   ",
    "",
    "   ",
  ]
end
