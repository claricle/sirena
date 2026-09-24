# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'stringio'

# Helpers for this file; `seed` needs a `root` example.
module CorpusSweepSpecHelpers
  def seed(type, name, source)
    FileUtils.mkdir_p(File.join(root, type))
    File.write(File.join(root, type, name), source)
  end

  def engine_returning(output)
    instance_double(Sirena::Engine, render: output).tap do |engine|
      allow(Sirena::Engine).to receive(:new).and_return(engine)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

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
