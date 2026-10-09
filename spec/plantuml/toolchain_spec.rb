# frozen_string_literal: true

require "json"
require "open3"

# Runs a tool and answers its combined output, or nil when it cannot start.
module ToolchainProbe
  def self.output(*command)
    text, = Open3.capture2e(*command)
    text
  rescue SystemCallError
    nil
  end
end

# The subject is a set of external binaries, not a class.
RSpec.describe "PlantUML toolchain" do # rubocop:disable RSpec/DescribeClass
  let(:pin) do
    path = File.expand_path("pin.json", __dir__)
    JSON.parse(File.read(path)).fetch("toolchain")
  end

  # Missing binary: a failure in CI, a loud skip on a dev machine.
  def probe(*command)
    text = ToolchainProbe.output(*command)
    return text if text

    message = "`#{command.join(' ')}` is not installed"
    raise message if ENV["CI"]

    skip "#{message}; install it to run the PlantUML specs locally"
  end

  it "runs the PlantUML version recorded in pin.json" do
    expect(probe("plantuml", "-version"))
      .to include("PlantUML version #{pin.fetch('plantuml_version')} ")
  end

  it "has Java on the path" do
    expect(probe("java", "-version")).to match(/version "\d+/)
  end

  it "has Graphviz on the path" do
    expect(probe("dot", "-V")).to match(/graphviz version \S+/)
  end
end
