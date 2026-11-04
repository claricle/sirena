# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (timeline)" do
  it_behaves_like "native corpus parity", "timeline"

  it_behaves_like "native edge parity", "timeline", [
    "timeline",
    "timeline\n",
    "  timeline  \n",
    "Timeline",
    "timeline\n  title History",
    "timeline\n  title\n",
    "timeline\n  title  \n  2002 : A",
    "timeline\r\n  title T\r\n  2002 : A\r\n",
    "timeline\n  section S\n    2002 : A\n    2004 : B : C",
    "timeline\n  section\n",
    "timeline\n  2002 : A\n  : B\n  : C : D",
    "timeline\n  : orphan",
    "timeline\n  2002 :\n",
    "timeline\n  2002 : \n",
    "timeline\n  2002 : http://example.com",
    "timeline\n  2002 : a:b : c",
    "timeline\n  2002 : <br>x",
    "timeline\n  2002 : A; B",
    "timeline\n  2002 : A;",
    "timeline\n  task one\n  task two",
    "timeline\n  section S\n  task one",
    "timeline\n  section S1\n  2002 : A\n  section S2\n  : B",
    "timeline\n  accTitle: Acc\n  accDescr: Desc",
    "timeline\n  accTitle:\n  2002 : A",
    "timeline\n  accDescr:\n",
    "timeline\n  accDescr {\n   multi\n   line\n  }\n  2002 : A",
    "timeline\n  accDescr {\n  }\n",
    "timeline\n  accDescr {\n unterminated",
    "timeline\n  my section here",
    "timeline\n%% comment\n  2002 : A %% trailing\n%% another",
    "%% lead\ntimeline\n  2002 : A",
    "timeline\n  2002 : é ü 日本",
    "timeline\n  \t2002\t:\tA\t",
    "timeline\n  2002 : A\n\n\n  2003 : B",
    "timeline extra\n  2002 : A",
    "",
    "   ",
  ]
end
