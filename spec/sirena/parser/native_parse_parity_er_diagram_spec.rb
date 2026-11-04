# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (er_diagram)" do
  it_behaves_like "native corpus parity", "er_diagram"

  it_behaves_like "native edge parity", "er_diagram", [
    "erDiagram",
    "erDiagram\n",
    "  erDiagram  \n",
    "%% lead\nerDiagram\n  A ||--o{ B : places",
    "erDiagram\r\n  A ||--o{ B : places\r\n  B ||--|| C : has\r\n",
    "erDiagram\n  A ||--o{ B : places %% trailing\n  C ||--|| D;",
    "erDiagram\n  A ||--o{ B :\n",
    "erDiagram\n  A ||--o{ B : \"quoted label\"",
    "erDiagram\n  A }o..o{ B : x\n  C }|==|{ D : y\n  E {} -- {} F",
    "erDiagram\n  A ||-- B",
    "erDiagram\n  erdiagram\n  A ||--o{ B",
    "erDiagram\n  ORDER-ITEM ||--o{ \"Line Item\" : has",
    "erDiagram\n  1 ||--o{ 1.5 : n\n  2abc ||--o{ B",
    "erDiagram\n  A:::x,y ||--o{ B:::z : l",
    "erDiagram\n  A:::x {\n  }\n  B:::a, b",
    "erDiagram\n  CAR {\n    string make PK \"the make\"\n    int year\n  }",
    "erDiagram\n  CAR {\n    string make PK,FK\n    int a FK , UK\n  }",
    "erDiagram\n  CAR {\n    ~timestamp with time zone~ at\n    Map~K, V~ m }",
    "erDiagram\n  CAR {\n    ~time zone~ at\n    Map~K, V~ m\n  }",
    "erDiagram\n  CAR {\n    a~b~c d\n    ~~ e\n  }",
    "erDiagram\n  CAR {\n    string make \"\"\n  }",
    "erDiagram\n  CAR {\n    string make \"é 日本\"\n  }",
    "erDiagram\n  CAR {\n    string make %% c\n    name\n  }",
    "erDiagram\n  CAR {\n    string make 'single'\n  }",
    "erDiagram\n  CAR {\n    string make PK PK\n  }",
    "erDiagram\n  CAR { string make }",
    "erDiagram\n  CAR {\n    string make\n",
    "erDiagram\n  classDef a,b fill:#f96,stroke:#333;\n  CAR:::a",
    "erDiagram\n  classDef a\n  classDef\n",
    "erDiagram\n  A\n  A\n  B ||--o{ A : x",
    "erDiagram\n  A ||--o{ B : x\n  garbage here",
    "erDiagram\n  \"\" ||--o{ B",
    "ERDIAGRAM\n  A ||--o{ B",
    "erDiagram A",
    "",
    "   ",
  ]
end
