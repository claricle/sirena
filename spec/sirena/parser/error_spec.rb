# frozen_string_literal: true

require 'spec_helper'
require 'sirena/parser/error'

RSpec.describe Sirena::Parser::ErrorParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses a simple error diagram' do
      source = 'error'

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Error)
      expect(diagram.message).to be_nil
    end

    it 'parses error diagram with message' do
      source = 'Error Diagrams'

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Error)
      expect(diagram.message).to eq('Diagrams')
    end

    it 'validates diagram structure' do
      source = 'error'

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
    end
  end

  # :corpus - sweeps the whole fixture directory and only asserts
  # `not_to raise_error`. Runs in `spec:corpus`, isolated from the
  # coverage-collecting `spec:unit` run: see .simplecov and Rakefile.
  describe 'fixture files', :corpus do
    Dir.glob('spec/mermaid/error/*.mmd').each do |fixture_file|
      it "parses #{File.basename(fixture_file)}" do
        source = File.read(fixture_file)

        expect { parser.parse(source) }.not_to raise_error
      end
    end
  end
end