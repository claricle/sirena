# frozen_string_literal: true

require "spec_helper"

# With the parsanol engine absent every native-declared type still parses
# the whole corpus through its Parslet grammar, identically to the forced
# Ruby path, and keeps raising positioned errors.
RSpec.describe Sirena::Parser::Native do
  NativeParity.native_directories.each do |directory|
    context "with the #{directory} parser and the engine absent" do
      around do |example|
        previous = ENV.fetch("SIRENA_NATIVE_PARSER", nil)
        ENV.delete("SIRENA_NATIVE_PARSER")
        described_class.reset!
        example.run
      ensure
        ENV["SIRENA_NATIVE_PARSER"] = previous
        described_class.reset!
      end

      before do
        allow(described_class).to receive(:require).with("parsanol")
          .and_raise(LoadError)
      end

      it "reports unavailable" do
        expect(described_class.available?).to be(false)
      end

      it "parses every fixture like the Ruby path" do
        expect(NativeParity.fixtures(directory)).to all(satisfy do |path|
          NativeParity.same_outcome?(directory, File.read(path))
        end)
      end

      it "still raises the positioned ParseError for bad input" do
        expect do
          NativeParity.parser_class(directory).new.parse("\u0001 not a diagram")
        end
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end
end
