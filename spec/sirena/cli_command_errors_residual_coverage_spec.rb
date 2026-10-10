# frozen_string_literal: true

require "spec_helper"
require "sirena/cli"
require "sirena/commands/batch"
require "sirena/commands/types"
require "sirena/commands/version"

RSpec.describe Sirena::Cli do
  it "tells Thor command failures require a nonzero exit" do
    expect(described_class.exit_on_failure?).to be(true)
  end

  [
    ["types", Sirena::Commands::TypesCommand],
    ["batch", Sirena::Commands::BatchCommand],
    ["version", Sirena::Commands::VersionCommand],
  ].each do |name, command_class|
    it "reports a #{name} command failure and exits one" do
      command = instance_double(command_class)
      allow(command_class).to receive(:new).and_return(command)
      allow(command).to receive(:run).and_raise(ArgumentError, "broken")

      expect { described_class.start([name]) }
        .to output("Error: broken\n").to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end
  end
end
