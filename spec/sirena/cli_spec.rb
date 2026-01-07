# frozen_string_literal: true

require 'spec_helper'
require 'sirena/cli'

RSpec.describe Sirena::Cli do
  describe 'version command' do
    it 'displays version information' do
      expect { described_class.start(['version']) }.to output(
        /sirena version #{Sirena::VERSION}/
      ).to_stdout
    end
  end

  describe 'types command' do
    it 'lists supported diagram types' do
      expect { described_class.start(['types']) }.to output(
        /Supported diagram types:/
      ).to_stdout
    end

    it 'includes all registered types' do
      output = capture_stdout { described_class.start(['types']) }
      expect(output).to include('flowchart')
      expect(output).to include('sequence')
      expect(output).to include('class_diagram')
      expect(output).to include('state_diagram')
      expect(output).to include('er_diagram')
      expect(output).to include('user_journey')
    end
  end

  describe 'help command' do
    it 'displays help information' do
      expect { described_class.start(['help']) }.to output(
        /Commands:/
      ).to_stdout
    end
  end

  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
