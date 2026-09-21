# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

unless defined?(CorpusSweep)
  CorpusSweep = Module.new
  load File.expand_path('../../scripts/corpus_sweep.rb', __dir__), CorpusSweep
end

RSpec.describe CorpusSweep do
  include CorpusSweepSpecHelpers

  # The script's top-level defs load as private instance methods.
  subject(:sweeper) do
    Class.new do
      include CorpusSweep

      public(*CorpusSweep.private_instance_methods(false))
    end.new
  end

  let(:root) { Dir.mktmpdir('corpus-sweep-spec') }
  let(:pie) { "pie\n  \"A\" : 1\n  \"B\" : 2\n" }
  let(:well_formed) { '<svg xmlns="http://www.w3.org/2000/svg"><text>a</text></svg>' }

  before { stub_const("#{described_class}::CORPUS_ROOT", root) }

  after { FileUtils.remove_entry(root) }

  describe '#render_result' do
    it 'classifies a rendering diagram as pass' do
      expect(sweeper.render_result(pie)).to eq(:pass)
    end

    it 'classifies an input the engine rejects as fail' do
      expect(sweeper.render_result("not a diagram at all\n")).to eq(:fail)
    end

    it 'classifies SVG-shaped output that is not well-formed XML as fail' do
      engine_returning('<svg><text>Alice<img src=</text></svg>')
      expect(sweeper.render_result(pie)).to eq(:fail)
    end

    it 'classifies an undeclared entity in the output as fail' do
      engine_returning('<svg><text>a&nbsp;b</text></svg>')
      expect(sweeper.render_result(pie)).to eq(:fail)
    end

    it 'classifies a self-closing svg root as fail' do
      engine_returning('<svg xmlns="http://www.w3.org/2000/svg"/>')
      expect(sweeper.render_result(pie)).to eq(:fail)
    end

    it 'classifies non-SVG output as fail' do
      engine_returning('hello')
      expect(sweeper.render_result(pie)).to eq(:fail)
    end

    it 'classifies a render that outlives the case timeout as timeout' do
      stub_const("#{described_class}::CASE_TIMEOUT", 0.05)
      engine = instance_double(Sirena::Engine)
      allow(engine).to receive(:render) { sleep 5 }
      allow(Sirena::Engine).to receive(:new).and_return(engine)
      expect(sweeper.render_result(pie)).to eq(:timeout)
    end

    it 'classifies well-formed SVG output as pass' do
      engine_returning(well_formed)
      expect(sweeper.render_result(pie)).to eq(:pass)
    end
  end

  describe 'sweep and --failing report' do
    before do
      seed('pie', '001_ok.mmd', pie)
      seed('pie', '002_bad.mmd', "not a diagram at all\n")
    end

    let(:results) { sweeper.sweep(['pie']) }

    it 'records one status per case file' do
      expect(results['pie'].transform_keys { |p| File.basename(p) })
        .to eq('001_ok.mmd' => :pass, '002_bad.mmd' => :fail)
    end

    it 'lists only non-passing cases as "status: corpus-relative path"' do
      out = capture_stdout { sweeper.report(results, list_failing: true) }
      expect(out.lines.grep(/\A(?:fail|timeout):/)).to eq(["fail: pie/002_bad.mmd\n"])
    end

    it 'prints the summary without a failing list when not asked' do
      out = capture_stdout { sweeper.report(results, list_failing: false) }
      expect(out).to include('TOTAL: 1/2 = 50.0%')
      expect(out.lines.grep(/\A(?:fail|timeout):/)).to be_empty
    end
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
