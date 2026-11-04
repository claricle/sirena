# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (gitgraph)" do
  it_behaves_like "native corpus parity", "gitgraph"

  it_behaves_like "native edge parity", "gitgraph", [
    "gitGraph",
    "gitGraph\n",
    "gitGraph:",
    "gitGraph LR:\n  commit",
    "gitGraph TB:\n  commit\n",
    "gitGraph BT :\n  commit",
    "gitGraph LR\n  commit",
    "gitgraph\n  commit",
    "gitGraph\r\n  commit\r\n  commit\r\n",
    "%% lead\ngitGraph\n  commit %% trailing\n%% end",
    "gitGraph\n  commit;\n  commit ;",
    "gitGraph\n  commit id: \"a\" tag: \"v1\" type: HIGHLIGHT",
    "gitGraph\n  commit id:a tag:v1 tag:v2 type:REVERSE",
    "gitGraph\n  commit tag: \"\"",
    "gitGraph\n  commit \"msg\"\n  commit msg: 'other'",
    "gitGraph\n  commit\"glued\"",
    "gitGraph\n  commit msg: \"a\\\"b\\n\\\\\"",
    "gitGraph\n  commit \"é ü 日本\" id: \"ü\"",
    "gitGraph\n  commit type: normal",
    "gitGraph\n  commit id: \"a\"\n  commit id: \"a\"",
    "gitGraph\n  branch dev order: 2\n  checkout dev\n  commit",
    "gitGraph\n  branch release/1.0.0\n  branch \"a b\"\n  commit",
    "gitGraph\n  branch a-\n  branch b.\n  branch c/",
    "gitGraph\n  branch .a",
    "gitGraph\n  branch",
    "gitGraph\n  branch dev\n  branch dev\n  commit",
    "gitGraph\n  checkout nope",
    "gitGraph\n  branch d\n  switch main\n  switch 'd'",
    "gitGraph\n  commit\n  branch d\n  commit\n  checkout main\n  merge d",
    "gitGraph\n  commit\n  branch d\n  commit\n  checkout main\n  " \
    "merge d tag: \"m\" random:\"x\" id: \"mm\"",
    "gitGraph\n  merge main",
    "gitGraph\n  commit id: \"x\"\n  cherry-pick id: \"x\"",
    "gitGraph\n  cherry-pick id: nope",
    "gitGraph\n  commit id: \"x\"\n  cherry-pick id:x parent:y tag:t",
    "gitGraph\n  accTitle: Title\n  accDescr: Desc\n  commit",
    "gitGraph\n  accTitle:\n  commit",
    "gitGraph\n  accDescr {\n    multi\n    line\n  }\n  commit",
    "gitGraph\n  accDescr {\n unterminated",
    "gitGraph\n  commit\n  bogus",
    "",
    "   ",
  ]
end
