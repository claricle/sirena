# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

# Runs scripts/corpus_sweep.rb over the pie corpus in a child process with
# Sirena::Engine#render replaced by one fixed string, so the script's own
# pass predicate is what is under test rather than any renderer.
module CorpusSweepRunner
  REPO_ROOT = File.expand_path("../..", __dir__)

  STUB = <<~RUBY
    require "bundler/setup"
    require "sirena"
    Sirena::Engine.class_eval { def render(_source, *) = ENV.fetch("FAKE_SVG") }
    ARGV.replace(["pie"])
    # corpus_sweep.rb only runs its report when loaded as the main program
    # ($PROGRAM_NAME == __FILE__); `load` alone leaves $PROGRAM_NAME as "-e"
    # and the script returns before printing anything.
    $PROGRAM_NAME = File.expand_path("scripts/corpus_sweep.rb")
    load "scripts/corpus_sweep.rb"
  RUBY

  def sweep_totals_for(svg)
    # bundler/setup must run before "sirena" is required in the child, or a
    # default gem (json) activates unpinned and Bundler's own activation
    # later conflicts with the Gemfile's pinned version.
    out, err, status = Open3.capture3({ "FAKE_SVG" => svg }, RbConfig.ruby, "-I", "lib", "-e", STUB, chdir: REPO_ROOT)
    raise "sweep did not run: #{err}" unless status.success?

    passed, total = out.match(%r{^TOTAL: (\d+)/(\d+)}).captures.map(&:to_i)
    { passed: passed, total: total }
  end
end

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
