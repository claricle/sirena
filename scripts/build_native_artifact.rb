#!/usr/bin/env ruby
# frozen_string_literal: true

# Assembles native_grammar/*.parg (prelude, one fragment per diagram type)
# into one mermaid.parg and compiles it with parsanol.
#
#   ruby scripts/build_native_artifact.rb PARG_OUT JSON_OUT [type ...]
#
# With type names, only the prelude and those fragments are assembled
# (a builder tests its own grammar without the others).
require "fileutils"

dir = File.expand_path("../native_grammar", __dir__)
parg_out, json_out, *types = ARGV
abort "usage: build_native_artifact.rb PARG_OUT JSON_OUT [type ...]" unless json_out

files = Dir.glob(File.join(dir, "*.parg"))
unless types.empty?
  files = files.select do |f|
    types.include?(File.basename(f,
                                 ".parg")) || File.basename(f).start_with?("00_")
  end
end
text = files.map { |f| File.read(f).rstrip }.join("\n\n")
File.write(parg_out, "#{text}\n}\n")
exec("parsanol", "parg", "compile", parg_out, "-o", json_out)
