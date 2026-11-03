# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/pie"
require "sirena/parser/info"

# The native (PARG artifact) path and the Parslet path must build the
# same model for every corpus fixture of the types the artifact covers.
module NativeParityHelper
  CORPUS = File.expand_path("../../mermaid", __dir__)
  PARSERS = {
    "pie" => Sirena::Parser::Pie,
    "info" => Sirena::Parser::Info,
  }.freeze

  module_function

  def fixtures(directory)
    Dir.glob(File.join(CORPUS, directory, "*.mmd"))
  end

  def with_native(native)
    previous = ENV.fetch("SIRENA_NATIVE_PARSER", nil)
    ENV["SIRENA_NATIVE_PARSER"] = native ? "1" : "ruby"
    yield
  ensure
    ENV["SIRENA_NATIVE_PARSER"] = previous
  end

  def outcome(directory, path, native:)
    with_native(native) do
      [:ok, PARSERS.fetch(directory).new.parse(File.read(path)).to_yaml]
    end
  rescue Sirena::Parser::ParseError => e
    [:error, e.message]
  end

  def native_answers(directory)
    with_native(true) do
      fixtures(directory).count do |path|
        Sirena::Parser::Native.parse(directory.to_sym, File.read(path))
      end
    end
  end

  def parslet_accepts(directory)
    fixtures(directory).count do |path|
      outcome(directory, path, native: false).first == :ok
    end
  end
end

RSpec.describe Sirena::Parser::Native do
  NativeParityHelper::PARSERS.each_key do |directory|
    context "with the #{directory} corpus" do
      it "has fixtures to compare" do
        expect(NativeParityHelper.fixtures(directory)).not_to be_empty
      end

      # Native also answers for fixtures whose Ruby builder then refuses
      # them (negative pie values), so it is never fewer.
      it "answers natively for every fixture Parslet accepts" do
        skip "parsanol engine absent" unless described_class.available?

        expect(NativeParityHelper.native_answers(directory))
          .to be >= NativeParityHelper.parslet_accepts(directory)
      end

      NativeParityHelper.fixtures(directory).each do |path|
        it "agrees with Parslet on #{File.basename(path)}" do
          expect(NativeParityHelper.outcome(directory, path, native: true))
            .to eq(NativeParityHelper.outcome(directory, path, native: false))
        end
      end
    end
  end
end
