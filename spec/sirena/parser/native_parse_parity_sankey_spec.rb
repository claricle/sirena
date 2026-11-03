# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (sankey)" do
  it_behaves_like "native corpus parity", "sankey"

  it_behaves_like "native edge parity", "sankey", [
    "sankey-beta",
    "sankey-beta\n",
    "  sankey-beta  \n",
    "sankey",
    "Sankey-beta",
    "sankey-beta\nA,B,10",
    "sankey-beta\nA,B,10\n",
    "sankey-beta\r\nA,B,10\r\nB,C,5.5\r\n",
    "sankey-beta\nA,B,10;\nB,C,5;",
    "sankey-beta\n  A , B , 10  \n",
    "sankey-beta\nA,B,10.",
    "sankey-beta\nA,B,.5",
    "sankey-beta\nA,B,-1",
    "sankey-beta\nA,B",
    "sankey-beta\nA,B,x",
    "sankey-beta\nA-1,B_2,3",
    "sankey-beta\nA B,C,3",
    "sankey-beta\nÉ,B,3",
    "sankey-beta\nA [Alpha]\nA,B,1",
    "sankey-beta\nA [Alpha]\nA [Beta]\nA,B,1",
    "sankey-beta\nA,B,1\nA [Late]",
    "sankey-beta\nA []\nA,B,1",
    "sankey-beta\nA [unterminated\nA,B,1",
    "sankey-beta\nA [multi\nline]\nA,B,1",
    "sankey-beta\nA [ spaced label ]",
    "sankey-beta\nA,A,1",
    "sankey-beta\nA,B,1\nB,A,1",
    "sankey-beta\nA,B,1\nB,C,1\nC,A,1",
    "sankey-beta\n%% c\nA,B,1 %% trailing\n%% d",
    "%% lead\nsankey-beta\nA,B,1",
    "sankey-beta\nA,B,1\n\n\nC,D,2",
    "sankey-beta\nA,B,1 extra",
    "sankey-beta\nA,B,1,2",
    "sankey-beta\tA,B,1",
    "",
    "   ",
  ]
end
