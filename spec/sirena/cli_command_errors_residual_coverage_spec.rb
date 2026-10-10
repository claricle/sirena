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
    context "with the #{name} command" do
      let(:command) { instance_double(command_class) }

      before do
        allow(command_class).to receive(:new).and_return(command)
        allow(command).to receive(:run).and_raise(ArgumentError, "broken")
      end

      it "reports a failure and exits one" do
        expect { described_class.start([name]) }
          .to output("Error: broken\n").to_stderr
          .and raise_error(SystemExit) do |error|
            raise "expected exit status 1" unless error.status == 1
          end
      end
    end
  end
end
