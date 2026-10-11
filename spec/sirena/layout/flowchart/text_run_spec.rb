# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart::TextRun do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) { Sirena::Layout::Flowchart.new.call(diagram, theme: theme) }
  let(:label) { scene.children.first.labels.first }
  let(:high_contrast_label) do
    high_contrast = Sirena::Theme::Registry.get(:high_contrast)
    Sirena::Layout::Flowchart.new.call(diagram, theme: high_contrast)
      .children.first.labels.first
  end

  def diagram
    Sirena::Parser::Flowchart.new.parse("flowchart TD\n  A[\"one<br>two\"]\n")
  end

  def rendered_xml
    Sirena::Renderer::Flowchart.new(theme: theme).render(scene).to_xml
  end

  def run_geometry(item)
    [item.content, item.x, item.y]
  end

  def replace_legacy_and_typed_geometry
    label.lines = ["stale", "values"]
    label.line_ys = [333.0, 444.0]
    label.text_y = 11.0
    label.runs.last.y = 222.0
  end

  it "publishes final parent and text-run geometry" do
    geometry = label.runs.map { |run| run_geometry(run) }

    expect([label.text_y, geometry])
      .to eq([40.6, [["one ", 51.416, nil], ["two", 51.416, 64.6]]])
  end

  it "scales final runs with the flowchart typography role" do
    expect([high_contrast_label.font_size, high_contrast_label.text_y,
            high_contrast_label.runs.map { |run| run_geometry(run) }])
      .to eq([18.0, 42.8,
              [["one ", 53.093, nil], ["two", 53.093, 69.8]]])
  end

  it "serializes typed runs without consulting legacy line arrays" do
    replace_legacy_and_typed_geometry

    expect(rendered_xml.scan(/<(?:text|tspan)[^>]* y="([^"]+)"/).flatten)
      .to eq(%w[11.0 222.0])
  end

  it "preserves the exact registered-default SVG bytes" do
    digest = "a9dfe17a70c654244cc6120e3401d2fc" \
             "5bbaaf734e5c9c7451ae1ed1796ff634"

    expect(Digest::SHA256.hexdigest(rendered_xml)).to eq(digest)
  end
end
