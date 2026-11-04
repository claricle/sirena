# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (quadrant)" do
  it_behaves_like "native corpus parity", "quadrant"

  it_behaves_like "native edge parity", "quadrant", [
    "quadrantChart",
    "quadrantChart\n",
    "  quadrantChart  \n",
    "quadrantchart\n",
    "quadrantChart\n  title Analysis",
    "quadrantChart\n  title\n",
    "quadrantChart\r\n  title T\r\n  A: [0.1, 0.2]\r\n",
    "quadrantChart\n  x-axis Low --> High",
    "quadrantChart\n  x-axis \"Low Cost\" --> \"High Cost\"",
    "quadrantChart\n  x-axis Low-->High",
    "quadrantChart\n  x-axis Low",
    "quadrantChart\n  x-axis \"\" --> High",
    "quadrantChart\n  y-axis Bottom --> Top\n  y-axis B2 --> T2",
    "quadrantChart\n  quadrant-1 Invest\n  quadrant-4 Drop",
    "quadrantChart\n  quadrant-5 Nope",
    "quadrantChart\n  quadrant-1\n",
    "quadrantChart\n  A: [0.3, 0.7]",
    "quadrantChart\n  A: [0.3, 0.7]\n",
    "quadrantChart\n  A B C: [0.3,0.7]",
    "quadrantChart\n  A:::cls: [0.3, 0.7]",
    "quadrantChart\n  A: [ 0.3 , 0.7 ]",
    "quadrantChart\n  A: [1, 2]",
    "quadrantChart\n  A: [-0.1, 0.2]",
    "quadrantChart\n  A: [0.3, 0.7] radius: 10",
    "quadrantChart\n  A: [0.3, 0.7] radius: 10.5, color: #ff0000",
    "quadrantChart\n  A: [0.3, 0.7] color: red , stroke-color: #abc",
    "quadrantChart\n  A: [0.3, 0.7] stroke-width: 2px, radius: 4",
    "quadrantChart\n  A: [0.3, 0.7] stroke-width: 2",
    "quadrantChart\n  A: [0.3, 0.7] color: #12",
    "quadrantChart\n  A: [0.3, 0.7] bogus: 1",
    "quadrantChart\n  A: [0.3, 0.7];",
    "quadrantChart\n  : [0.3, 0.7]",
    "quadrantChart\n  é 日本: [0.3, 0.7]",
    "quadrantChart\n  classDef c1 color: #109060, radius: 10",
    "quadrantChart\n  classDef c1 fill:#fff",
    "quadrantChart\n  classDef c1 \n",
    "quadrantChart\n  classDef c1\n",
    "quadrantChart\n%% comment\n  A: [0.3, 0.7] %% trailing\n%% end",
    "%% lead\nquadrantChart\n  A: [0.3, 0.7]",
    "quadrantChart\n  title A\n  title B\n",
    "quadrantChart extra\n  A: [0.3, 0.7]",
    "",
    "   ",
  ]
end
