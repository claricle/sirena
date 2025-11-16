# frozen_string_literal: true

require 'spec_helper'
require 'sirena/parser/info'

RSpec.describe Sirena::Parser::InfoParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses a simple info diagram' do
      source = 'info'

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Info)
      expect(diagram.show_info).to be false
    end

    it 'parses info diagram with showInfo flag' do
      source = 'info showInfo'

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Info)
      expect(diagram.show_info).to be true
    end

    it 'validates diagram structure' do
      source = 'info'

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
    end
  end

  describe 'fixture files' do
    Dir.glob('spec/mermaid/info/*.mmd').each do |fixture_file|
      it "parses #{File.basename(fixture_file)}" do
        source = File.read(fixture_file)

        expect { parser.parse(source) }.not_to raise_error
      end
    end
  end
end