#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse-time comparison of the native (PARG) path and the Parslet path on
# the Mermaid corpus fixtures of the types the artifact covers.
#
#   bundle exec ruby scripts/benchmark_native_parse.rb [rounds]

require "benchmark"
require "json"
require_relative "../lib/sirena"
require_relative "native_types"

ROUNDS = Integer(ARGV.fetch(0, 5))
CORPUS = File.expand_path("../spec/mermaid", __dir__)
TYPES = NativeTypes::TYPES.filter_map do |directory, (path, name)|
  require_relative "../lib/sirena/parser/#{path}"
  parser_class = Sirena::Parser.const_get(name)
  [directory, parser_class] if parser_class.native
end.to_h.freeze

def run(parser_class, sources, native)
  ENV["SIRENA_NATIVE_PARSER"] = native ? "1" : "ruby"
  parser = parser_class.new
  sources.each do |source|
    parser.parse(source)
  rescue Sirena::Parser::ParseError
    nil
  end
end

def best_of(parser_class, sources, native)
  run(parser_class, sources, native)
  timings = Array.new(ROUNDS) do
    Benchmark.realtime { run(parser_class, sources, native) }
  end
  timings.min
end

report = TYPES.map do |directory, parser_class|
  paths = Dir.glob(File.join(CORPUS, directory, "*.mmd"))
  sources = paths.map { |path| File.read(path) }
  lines = (1..2000).map { |i| "  \"slice #{i}\" : #{i}" }
  big = "pie title Big\n#{lines.join("\n")}\n"
  rows = { "corpus (#{sources.size} files)" => sources }
  rows["large pie (2000 slices)"] = [big] if directory == "pie"
  rows.map do |name, set|
    ruby = best_of(parser_class, set, false)
    native = best_of(parser_class, set, true)
    { type: directory, input: name,
      ruby_ms: (ruby * 1000).round(2), native_ms: (native * 1000).round(2),
      speedup: (ruby / native).round(2) }
  end
end.flatten

puts JSON.pretty_generate(report)
