# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe SpecSupport::LayoutParity::CohortRunner do
  subject(:error_stage) do
    runner.run
    captured.fetch(:render_error).fetch(:error_stage)
  end

  let(:root) { Dir.mktmpdir }
  let(:captured) { {} }
  let(:doubles) do
    {
      comparator: class_double(SpecSupport::LayoutParity::CaseComparator),
      renderer: instance_double(Sirena::Engine),
    }
  end
  let(:runner) do
    described_class.new(paths:, **doubles,
                        detector: ->(_source) { :flowchart })
  end

  before do
    seed_case
    allow(renderer).to receive(:render).and_raise(error_class, "boom")
    allow(comparator).to receive(:compare) do |**arguments|
      captured.replace(arguments)
      :compared
    end
  end

  after { FileUtils.remove_entry(root) }

  {
    Sirena::Engine::DiagramTypeError => "detect",
    Sirena::Parser::ParseError => "parse",
    Sirena::Renderer::RenderError => "render",
    StandardError => "unknown",
  }.each do |raised_class, expected_stage|
    context "when rendering raises #{raised_class}" do
      let(:error_class) { raised_class }

      it "records the #{expected_stage} pipeline stage" do
        expect(error_stage).to eq(expected_stage)
      end
    end
  end

  def seed_case
    FileUtils.mkdir_p(File.join(paths.fetch(:corpus), "flowchart"))
    FileUtils.mkdir_p(File.join(paths.fetch(:references), "flowchart"))
    File.write(paths.fetch(:scoreboard), JSON.generate([scoreboard_row]))
    File.write(corpus_path, "flowchart LR\nA")
    File.write(reference_path, '<svg viewBox="0 0 1 1"/>')
  end

  def paths
    {
      scoreboard: File.join(root, "scoreboard.json"),
      corpus: File.join(root, "corpus"),
      references: File.join(root, "references"),
    }
  end

  def renderer
    doubles.fetch(:renderer)
  end

  def comparator
    doubles.fetch(:comparator)
  end

  def scoreboard_row
    { "case" => "flowchart/example.mmd", "verdict" => "valid", "pass" => true }
  end

  def corpus_path
    File.join(paths.fetch(:corpus), "flowchart/example.mmd")
  end

  def reference_path
    File.join(paths.fetch(:references), "flowchart/example.svg")
  end
end
