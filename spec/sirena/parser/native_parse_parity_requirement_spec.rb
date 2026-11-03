# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (requirement)" do
  it_behaves_like "native corpus parity", "requirement"

  it_behaves_like "native edge parity", "requirement", [
    "requirementDiagram",
    "requirementDiagram\n",
    "  requirementDiagram  \n",
    "requirementDiagram\r\n  requirement r {\r\n    id: 1\r\n  }\r\n",
    "requirementDiagram\n  requirement r {\n    id: 1\n    text: some\n    " \
    "risk: high\n    verifymethod: test\n  }",
    "requirementDiagram\n  functionalRequirement f { id: 1 }",
    "requirementDiagram\n  interfaceRequirement i {\n  }",
    "requirementDiagram\n  performanceRequirement p {}",
    "requirementDiagram\n  physicalRequirement q {\n    id: 1\n  }",
    "requirementDiagram\n  designConstraint d {\n    id: 1\n  }",
    "requirementDiagram\n  requirement r:::a,b {\n    id: 1\n  }",
    "requirementDiagram\n  requirement r :::a {\n    id: 1\n  }",
    "requirementDiagram\n  requirement r\n  {\n    id: 1\n  }",
    "requirementDiagram\n  requirement r {\n    id: 1",
    "requirementDiagram\n  requirement {\n    id: 1\n  }",
    "requirementDiagram\n  requirement r {\n    bogus: 1\n  }",
    "requirementDiagram\n  requirement r {\n    id:\n  }",
    "requirementDiagram\n  requirement r {\n    id:   spaced  \n  }",
    "requirementDiagram\n  requirement r {\n    text: é 日本 %% not comment\n  }",
    "requirementDiagram\n  element e {\n    type: simulation\n    " \
    "docref: ref\n  }",
    "requirementDiagram\n  element e:::c {\n  }",
    "requirementDiagram\n  e - satisfies -> r",
    "requirementDiagram\n  e-satisfies->r",
    "requirementDiagram\n  e - contains - > r",
    "requirementDiagram\n  e - copies -> r\n  a - derives -> b\n  " \
    "c - verifies -> d\n  f - refines -> g\n  h - traces -> i",
    "requirementDiagram\n  e - unknown -> r",
    "requirementDiagram\n  accTitle: My title",
    "requirementDiagram\n  accTitle:\n",
    "requirementDiagram\n  accTitle\n  :\n  later",
    "requirementDiagram\n  accTitle :　T ",
    "requirementDiagram\n  accDescr: Desc",
    "requirementDiagram\n  accDescr {\n   multi\n   line\n  }",
    "requirementDiagram\n  accDescr {}",
    "requirementDiagram\n  accDescr {x}accTitle: y",
    "requirementDiagram\n  accDescr {\n unterminated",
    "requirementDiagram\n  style r fill:#f9f,stroke:#333,stroke-width:4px",
    "requirementDiagram\n  style a, b fill:#f9f",
    "requirementDiagram\n  style a,b fill:#f9f, foo",
    "requirementDiagram\n  style r",
    "requirementDiagram\n  classDef c fill:#f9f,stroke:#333",
    "requirementDiagram\n  classDef c",
    "requirementDiagram\n  class a,b c,d",
    "requirementDiagram\n  class a c",
    "requirementDiagram\n  class a",
    "requirementDiagram\n  %% comment\n  requirement r { id: 1 } %% tail\n",
    "requirementDiagram\n  requirement r { id: 1 };",
    "requirementDiagram\n  requirement r { id: 1 } trailing",
    "requirementdiagram",
    "%% lead\nrequirementDiagram\n  requirement r { id: 1 }",
    "",
    "   ",
  ]
end
