# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (gantt)" do
  it_behaves_like "native corpus parity", "gantt"

  it_behaves_like "native edge parity", "gantt", [
    "gantt",
    "gantt\n",
    "  gantt  \n",
    "gantt\ntitle",
    "gantt\ntitle T",
    "gantt\n  title   Project  \n  dateFormat YYYY-MM-DD",
    "gantt\r\n  title T\r\n  section S\r\n  A :a1, 2024-01-01, 3d\r\n",
    "gantt\n  axisFormat %m/%d\n  tickInterval 1week",
    "gantt\n  excludes weekends\n  excludes 2024-01-01",
    "gantt\n  weekend friday\n  inclusiveEndDates\n  todayMarker off",
    "gantt\n  inclusiveEndDates extra",
    "gantt\n  todayMarker stroke-width:2px",
    "gantt\n  accTitle: Acc\n  accDescr: Desc",
    "gantt\n  accTitle:\n  A :a1, 2024-01-01, 1d",
    "gantt\n  accDescr {\n   multi\n   line\n  }\n  A :a1, 2024-01-01, 1d",
    "gantt\n  accDescr {\n unterminated",
    "gantt\n  section Plan; \n  A :a1, 2024-01-01, 3d;",
    "gantt\n  A :a1, 2024-01-01, 3d %% trailing\n  B :after a1, 2d",
    "gantt\n%% comment\n  A :done, crit, a1, 2024-01-01, 2024-01-05",
    "gantt\n  A :milestone, m1, 2024-01-01, 0d",
    "gantt\n  A :until b1, 2d\n  B :b1, 2024-02-01, 1d",
    "gantt\n  A :after a b c, 2024-03-01",
    "gantt\n  A :20240101, 20240103",
    "gantt\n  A : someid",
    "gantt\n  A :a1 ,2024-01-01 , 3d",
    "gantt\n  A :a1, , 3d",
    "gantt\n  A :",
    "gantt\n  A",
    "gantt\n  : a1, 2024-01-01",
    "gantt\n  Plan: é ü 日本 :a1, 2024-01-01, 2d",
    "gantt\n  A :a1, 2024-01-01, 3d\n  click a1 href https://x.test",
    "gantt\n  click a1 call cb(arg)\n  A :a1, 2024-01-01, 3d",
    "gantt\n  click 1a href x",
    "gantt\n  click a1 foo",
    "gantt\n  sectionX",
    "gantt\n  section",
    "Gantt\n  A :a1, 2024-01-01, 3d",
    "gantt chart\n  A :a1, 2024-01-01, 3d",
    "%% lead\ngantt\n  A :a1, 2024-01-01, 3d",
    "",
    "   ",
  ]
end
