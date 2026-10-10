# frozen_string_literal: true

# Untagged: runs in every job, with no PlantUML installed.
RSpec.describe ToolchainProbe do
  let(:prober) do
    Class.new do
      include ToolchainProbe

      attr_reader :skipped

      def skip(message) = @skipped = message
    end.new
  end
  let(:missing) { "plantuml-does-not-exist-xyz" }

  before do
    allow(ENV).to receive(:[]).and_call_original
  end

  it "fails in CI when the binary is missing" do
    allow(ENV).to receive(:[]).with("CI").and_return("true")
    expect { prober.probe(missing) }.to raise_error(/not installed/)
  end

  it "skips on a dev machine when the binary is missing" do
    allow(ENV).to receive(:[]).with("CI").and_return(nil)
    prober.probe(missing)
    expect(prober.skipped).to include("not installed")
  end
end
