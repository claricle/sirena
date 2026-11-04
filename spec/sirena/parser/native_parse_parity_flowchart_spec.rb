# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (flowchart)" do
  it_behaves_like "native corpus parity", "flowchart"

  it_behaves_like "native edge parity", "flowchart", [
    "graph",
    "graph TD",
    "graph TD\n",
    "flowchart LR\nA-->B",
    "flowchart-elk TD\nA-->B",
    "graph TD\r\nA-->B\r\n",
    "graph TD\rA-->B\r",
    "graph\nTD",
    "graph TDx\nA",
    "graph ;A",
    "graph TD;A-->B",
    "graph TD %% c\nA",
    "%% lead\ngraph TD\nA",
    "Graph TD\nA",
    "graph <\nA-->B",
    "graph v\nA-->B",
    "graph TD\nA[Start]-->B(Round)-->C{Rhomb}",
    "graph TD\nA([stadium])-->B[[sub]]-->C[(db)]-->D((c))-->E(((dc)))",
    "graph TD\nA>asym]-->B{{hex}}-->C[/para/]-->D[\\alt\\]",
    "graph TD\nE[/trap\\]-->F[\\trap/]",
    "graph TD\nA[]-->B[ ]-->C()",
    "graph TD\nA[\"q ) text\"]-->B(\"a (1)\")",
    "graph TD\nA[hello ) world]",
    "graph TD\nA(\"unclosed)",
    "graph TD\nA-->B\nA-->C;\nB-->D;;C-->D",
    "graph TD\nA---B\nA===B\nA-.-B\nA~~~B\nA<-->B\nAx--xB\nAo--oB",
    "graph TD\nA-->|label|B\nA-- text -->B\nA== t ==>B\nA-. t .->B",
    "graph TD\nA-- \"quoted --\" -->B",
    "graph TD\nA -- --> B",
    "graph TD\nA & B --> C & D",
    "graph TD\nA e1@--> B\ne1@{ animate: true }",
    "graph TD\nA@{ shape: rect, label: \"x\" }\nB@{ shape: nope }",
    "graph TD\nA@{ label: a^b }",
    "graph TD\nA:::cls --> B:::other",
    "graph TD\nsubgraph s [Title]\nA-->B\nend",
    "graph TD\nsubgraph s Free title\nA\nend",
    "graph TD\nsubgraph one\nsubgraph two\nA\nend\nend",
    "graph TD\nsubgraph s\nA",
    "graph TD\nsubgraph end\nA\nend",
    "graph TD\nsubgraph \"quoted id\" [T]\nA\nend; B-->C",
    "graph TD\nsubgraph s\ndirection LR\nA-->B\nend",
    "graph TD\nstyle A fill:#f9f,stroke:#333\nA",
    "graph TD\nstyle A fill:red;B",
    "graph TD\nstyle A fill:#f9f;B;C",
    "graph TD\nclassDef a,b fill:#f9f\nclass A a\nA",
    "graph TD\nA-->B\nlinkStyle 0 stroke:red\nlinkStyle default stroke:blue",
    "graph TD\nA-->B\nlinkStyle 3 stroke:red",
    "graph TD\nA\nclick A \"https://x\" \"tip\" _blank\nclick A call cb()",
    "graph TD\nA\nclick A href",
    "graph TD\naccTitle: Title\naccDescr: Desc\nA",
    "graph TD\naccDescr {\n multi\n}\nA",
    "graph TD\nA %% c",
    "graph TD\nA --> B %% c",
    "graph TD\n\tA --> B\n\t;\n",
    "graph TD\nA-->",
    "graph TD\nA[unterminated",
    "graph TD\n1-->2\na.b-->a/b\nA-b-->C",
    "graph TD\né-->中",
    "graph TD\nA-->B-->C-->D",
    "graph TD\nend",
    "graph TD\nA -->B",
    "graph TD\nclick\nA",
  ]

  it "leaves a diagram nested deeper than the builder allows to Parslet" do
    source = "graph TD\n#{"subgraph s\n" * 80}A\n#{"end\n" * 80}"

    expect(NativeParity.outcome("flowchart", source, native: true))
      .to eq(NativeParity.outcome("flowchart", source, native: false))
  end
end
