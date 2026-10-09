# frozen_string_literal: true

require "json"

# Tagged :toolchain, so it runs only with `--tag toolchain` (the
# plantuml-toolchain CI job). Other jobs have no PlantUML installed.
RSpec.describe ToolchainProbe, :toolchain do
  include described_class

  let(:pin) do
    path = File.expand_path("pin.json", __dir__)
    JSON.parse(File.read(path)).fetch("toolchain")
  end

  it "finds the PlantUML version recorded in pin.json" do
    expect(probe("plantuml", "-version"))
      .to include("PlantUML version #{pin.fetch('plantuml_version')} ")
  end

  it "finds Java on the path" do
    expect(probe("java", "-version")).to match(/version "\d+/)
  end

  it "finds Graphviz on the path" do
    expect(probe("dot", "-V")).to match(/graphviz version \S+/)
  end
end
