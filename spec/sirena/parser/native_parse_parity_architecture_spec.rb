# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (architecture)" do
  it_behaves_like "native corpus parity", "architecture"

  it_behaves_like "native edge parity", "architecture", [
    "architecture-beta",
    "architecture-beta\n",
    "  architecture-beta  \n",
    "architecture-beta\r\n  group g(cloud)[G]\r\n  service s in g\r\n",
    "architecture-beta\n  group g(cloud)[G] in p",
    "architecture-beta\n  group g",
    "architecture-beta\n  group g[Only label]",
    "architecture-beta\n  group g(icon)",
    "architecture-beta\n  service db(database)[DB] in g",
    "architecture-beta\n  service é(db)",
    "architecture-beta\n  service db()[x]",
    "architecture-beta\n  service db(a)[]",
    "architecture-beta\n  junction j in g",
    "architecture-beta\n  junction j(icon)",
    "architecture-beta\n  a:L --> R:b",
    "architecture-beta\n  a:LR -- TB:b : label text",
    "architecture-beta\n  a --> b",
    "architecture-beta\n  a-->b",
    "architecture-beta\n  a L--R b",
    "architecture-beta\n  a:L --> b :  spaced  ",
    "architecture-beta\n  title My Title",
    "architecture-beta\n  title",
    "architecture-beta\n  title --> x",
    "architecture-beta\n  accTitle: Acc\n  accDescr: Desc",
    "architecture-beta\n  accTitle:",
    "architecture-beta\n  accDescr {\n    multi\n  }",
    "architecture-beta\n  accDescr{}",
    "architecture-beta\n  accDescr {\n unterminated",
    "architecture-beta\n  %% comment\n  service s ;\n  service t %% tail\n",
    "architecture-beta\n  service s;service t",
    "architecture-beta\n  service s extra",
    "Architecture-beta",
    "architecture",
    "%% lead\narchitecture-beta\n  service s",
    " architecture-beta",
    "architecture-beta\n\u000b  service s",
    "",
    "   ",
  ]
end
