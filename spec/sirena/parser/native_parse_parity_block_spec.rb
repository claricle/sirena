# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (block)" do
  it_behaves_like "native corpus parity", "block"

  it_behaves_like "native edge parity", "block", [
    "block-beta",
    "block-beta\n",
    "  block-beta  \n",
    "block-beta\r\n  columns 2\r\n  A\r\n  B\r\n",
    "block-beta\n  columns 3\n  A B",
    "block-beta\n  columns",
    "block-beta\n  columns  2",
    "block-beta\n  columns 99999999999999999999\n  A",
    "block-beta\n  A\n  space\n  B",
    "block-beta\n  A[]\n  B[\"\"]\n  C[ x ]",
    "block-beta\n  A[\"quoted\"]:3\n  B(( c ))\n  D((\"d\")):2",
    "block-beta\n  A [spaced]",
    "block-beta\n  A:2",
    "block-beta\n  A:",
    "block-beta\n  é[é]\n  B",
    "block-beta\n  日本[日本]",
    "block-beta\n  ab[multi\nline]\n  C",
    "block-beta\n  arr<[\"&nbsp;\"]>(down)",
    "block-beta\n  A[é日本]\n  arr<[]>(up)",
    "block-beta\n  A[日本] --> B\n  arr<[é]>(left)",
    "block-beta\n  arr<[x]>(diagonal)",
    "block-beta\n  A --> B\n  C --- D\n  E-->F\n  G---H",
    "block-beta\n  A -- B",
    "block-beta\n  \"A\" --> B",
    "block-beta\n  \"A\"",
    "block-beta\n  A[\"x\"] --> B",
    "block-beta\n  block:o\n    columns 2\n    A\n    block:i\n      B\n    " \
    "end\n  end",
    "block-beta\n  block\n    A\n  end\n  space\n  block\n  end",
    "block-beta\n  block:g\n  end",
    "block-beta\n  block:g\n    A",
    "block-beta\n  blockA\n  endB\n  spaced",
    "block-beta\n  end",
    "block-beta\n  block:\n    A\n  end",
    "block-beta\n  style A fill:#f9f,stroke:#333,stroke-width:4px",
    "block-beta\n  style A fill:#f9f,stroke:#333, foo",
    "block-beta\n  style A color:red",
    "block-beta\n  style A",
    "block-beta\n  style\tA fill:red",
    "block-beta\n  %% comment\n  A %% tail\n  B;\n  C ;",
    "block-beta\n  A;B",
    "Block-beta",
    "block-beta extra",
    "block\n  A",
    "%% lead\nblock-beta\n  A",
    "",
    "   ",
  ]
end
