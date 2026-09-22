# frozen_string_literal: true

require "spec_helper"

RSpec.describe "scripts/corpus_sweep.rb", type: :task do
  include CorpusSweepRunner

  it "counts a well-formed SVG as a pass for every case" do
    totals = sweep_totals_for('<svg xmlns="http://www.w3.org/2000/svg"><text>a</text></svg>')

    expect(totals[:total]).to be_positive
    expect(totals[:passed]).to eq(totals[:total])
  end

  # Sirena's real output opens `<svg` followed by a newline, not a space, so
  # the root-tag shape is pinned on every spelling the predicate accepts.
  {
    "a newline after <svg" => %(<svg\n  xmlns="http://www.w3.org/2000/svg"\n  width="1"></svg>\n),
    "an xml declaration before the root" => %(<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg"></svg>),
    "leading whitespace before the root" => %(\n  <svg xmlns="http://www.w3.org/2000/svg"></svg>),
    "trailing whitespace after </svg>" => %(<svg xmlns="http://www.w3.org/2000/svg"></svg>\n\n),
    "a bare <svg> root" => "<svg></svg>",
    "an entity-like text inside a comment" => "<svg><!-- &nbsp; --></svg>",
    "an entity-like text inside CDATA" => "<svg><![CDATA[&nbsp;]]></svg>",
    "an entity-like text inside a processing instruction" => "<svg><?x &nbsp; ?></svg>",
    "a numeric character reference" => "<svg><text>&#169;</text></svg>"
  }.each do |label, svg|
    it "counts #{label} as a pass for every case" do
      totals = sweep_totals_for(svg)

      expect(totals[:passed]).to eq(totals[:total])
    end
  end

  {
    "an unescaped <br> inside <text> (svg-shaped but not XML)" => "<svg><text>a<br></text></svg>",
    "an undeclared entity reference" => "<svg><text>a&nbsp;b</text></svg>",
    "output that is not an svg at all" => "<html></html>",
    "an svg that does not open the document" => "<!-- x --><svg></svg>",
    "an svg root that is not closed at the end" => "<svg></svg><!-- x -->",
    "an entity after a CDATA section that holds a comment opener" => "<svg><![CDATA[<!--]]>&nbsp;<!-- --></svg>",
    "an entity after a processing instruction that holds a comment opener" => "<svg><?x <!-- ?>&nbsp;<?y --> ?></svg>"
  }.each do |label, svg|
    it "counts #{label} as a failure for every case" do
      expect(sweep_totals_for(svg)[:passed]).to eq(0)
    end
  end
end
