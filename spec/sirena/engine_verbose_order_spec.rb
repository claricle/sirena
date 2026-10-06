# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

module VerboseOrderHelper
  def detected
    ["Starting render pipeline...", "Detected diagram type: flowchart"]
  end

  def parsing
    detected + ["Retrieved handlers for flowchart", "Parsing diagram..."]
  end

  def success_stages
    parsing + [
      "Parse complete: Sirena::Diagram::Flowchart",
      "Transforming diagram to graph...", "Transform complete",
      "Computing layout...", "Layout complete (using fallback positioning)",
      "Rendering to SVG...", "SVG render complete"
    ]
  end

  def render_quietly(source)
    engine.render(source, verbose: true)
  rescue Sirena::Error
    nil
  end
end

RSpec.describe Sirena::Engine do
  include VerboseOrderHelper

  let(:log_output) { StringIO.new }
  let(:logger) do
    Logger.new(log_output).tap do |l|
      l.formatter = proc { |_s, _t, _p, msg| "#{msg}\n" }
    end
  end
  let(:engine) { described_class.new(logger: logger) }
  let(:lines) { log_output.string.lines(chomp: true) }

  it "logs every stage in order under verbose on success" do
    render_quietly("graph TD\nA-->B")

    expect(lines[0...-1]).to eq(success_stages)
  end

  it "ends with the byte count on success" do
    render_quietly("graph TD\nA-->B")

    expect(lines.last).to match(/\ARender complete, \d+ bytes\z/)
  end

  it "stops after 'Parsing diagram...' when the parser raises" do
    render_quietly("graph TD\nA-->")

    expect(lines).to eq(parsing)
  end

  it "logs only the detection line when the preamble is degenerate" do
    render_quietly("%%\ngraph TD\nA-->B")

    expect(lines).to eq(detected)
  end

  it "logs only the start line when no type is detected" do
    render_quietly("hello")

    expect(lines).to eq(["Starting render pipeline..."])
  end
end
