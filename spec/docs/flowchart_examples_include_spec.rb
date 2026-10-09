# frozen_string_literal: true

require "spec_helper"

module FlowchartExamplesIncludeSpec
  ROOT = File.expand_path("../..", __dir__)
  HOST = File.join(ROOT, "docs/_diagram_types/flowchart.adoc")
  INCLUDE = File.join(ROOT, "docs/_diagram_types/examples/flowchart-examples.adoc")
  DIRECTIVE = /^(?<line>include::(?<target>[^\[]+)\[\])$/

  module_function

  def host_source
    File.read(HOST)
  end

  def include_source
    File.read(INCLUDE)
  end

  def include_match
    DIRECTIVE.match(host_source)
  end

  def resolved_include
    File.expand_path(include_match[:target], File.dirname(HOST))
  end

  def expanded_host_source
    host_source.sub(include_match[:line], include_source)
  end
end

RSpec.describe FlowchartExamplesIncludeSpec do
  it "keeps the generated examples as a front-matter-free include" do
    expect(described_class.include_source).not_to match(/\A---\R.*?^---\R/m)
  end

  it "resolves the flowchart include to the tracked generated source" do
    resolved = described_class.resolved_include

    expect([resolved, File.file?(resolved)]).to eq([described_class::INCLUDE, true])
  end

  it "expands the generated example into the flowchart page" do
    expanded = described_class.expanded_host_source

    expect(expanded).to include(
      "==== Example 1: Basic Flowchart",
      "Start([Start]) --> Process[Process Data]",
    )
  end
end
