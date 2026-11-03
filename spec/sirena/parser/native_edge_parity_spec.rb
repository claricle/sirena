# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/pie"
require "sirena/parser/info"

# Hand-picked inputs at the edges of the PARG rules: both parse paths must
# build the same model, or fail the same way.
module NativeEdgeHelper
  def self.outcome(parser_class, source, native:)
    previous = ENV.fetch("SIRENA_NATIVE_PARSER", nil)
    ENV["SIRENA_NATIVE_PARSER"] = native ? "1" : "ruby"
    [:ok, parser_class.new.parse(source).to_yaml]
  rescue Sirena::Parser::ParseError => e
    [:error, e.message]
  ensure
    ENV["SIRENA_NATIVE_PARSER"] = previous
  end
end

RSpec.describe Sirena::Parser::Native do
  pie_sources = [
    "pie",
    "pie\n",
    "  pie  \n",
    "pie showData",
    "pie title Pets",
    "pie title: Pets",
    "pie showData title Pets  ",
    "pie title",
    "pie title:\n  \"a\" : 1",
    "pie\ntitle   T  \n\"a\" : 1",
    "pie\ntitle\n",
    "pie\r\n  \"a\" : 1\r\n  \"b\" : 2\r\n",
    "pie\n  'a' : 1\n  \"b\\\"c\" : 2.5",
    "pie\n  \"\" : 1",
    "pie\n  \"é ü 日本\" : 3",
    "pie\n  \"a\" : -1",
    "pie\n  \"a\" : 5.",
    "pie\n  \"a\" : .5",
    "pie\n  \"a\" : 1e3",
    "pie\n  \"a\" : 1 %% trailing\n  \"b\" : 2;",
    "pie\n%% comment\n  \"a\" : 1\n%% another",
    "pie\n  accTitle: Acc\n  accDescr: Desc\n  \"a\" : 1",
    "pie\n  accTitle:\n  \"a\" : 1",
    "pie\n  accDescr {\n   multi\n   line\n  }\n  \"a\" : 1",
    "pie\n  accDescr {\n  }\n",
    "pie\n  accDescr {\n unterminated",
    "pie\n  \"a\" 1",
    "pie\n  a : 1",
    "pie chart\n  \"a\" : 1",
    "Pie\n  \"a\" : 1",
    "pie\n  \"a\" : 1\n  \"a\" : 2",
    "%% lead\npie\n  \"a\" : 1",
    "",
    "   ",
  ]
  info_sources = [
    "info",
    "info\n",
    "info showInfo",
    "info  showInfo  ",
    "info\n  showInfo",
    "info\nshowInfo\nshowInfo",
    "info showInfo\nshowInfo",
    "info other",
    "info\nother",
    "info showInfoX",
    "Info",
    "info %% c\n",
    "info;\n",
    "%% x\ninfo showInfo ;",
    "",
  ]

  {
    Sirena::Parser::Pie => pie_sources,
    Sirena::Parser::Info => info_sources,
  }.each do |parser_class, sources|
    sources.each do |source|
      it "#{parser_class.name.split('::').last} agrees on #{source.inspect}" do
        ruby = NativeEdgeHelper.outcome(parser_class, source, native: false)
        native = NativeEdgeHelper.outcome(parser_class, source, native: true)

        expect(native).to eq(ruby)
      end
    end
  end
end
