# frozen_string_literal: true

require_relative "../../error"
require_relative "include/blocks"
require_relative "include/finder"

module Sirena
  module Notation
    module PlantUML
      # PlantUML's file preprocessor: `!include FILE[!SELECTOR]` and
      # `!includesub FILE!NAME`, expanded into the source before any family
      # reads it. `!startsub NAME` / `!endsub` marker lines are dropped from
      # the text that is kept.
      #
      # Measured against PlantUML 1.2026.6 (`java -jar plantuml.jar -tsvg`):
      #
      # - `!include FILE!N`, `!include FILE!ID` and a bare `!include FILE`
      #   all take the FIRST `@start...` block of FILE (`!2`, `!7`, `!NOPE`
      #   and `!BACKEND` on a file whose first block is something else all
      #   drew the first block). The selector is accepted and ignored, which
      #   is what the oracle draws.
      # - `!includesub FILE!NAME` takes every `!startsub NAME` .. `!endsub`
      #   stretch of FILE, in file order.
      # - a relative path is looked up beside the including file, then in the
      #   include path (`-Dplantuml.include.path`).
      # - a file that cannot be found is an error.
      #
      # Unlike the JAR, which reads `../../etc/hosts` from anywhere, a path is
      # only read when it resolves (symlinks followed) inside an allowed root:
      # the directory of the source being rendered or an include-path entry.
      module Include
        # A refused or failed include; a Sirena::Error so the engine
        # propagates it unwrapped.
        class Error < Sirena::Error; end

        DIRECTIVE = /\A!(?<kind>include|includesub)[ \t]+(?<spec>\S.*)\z/
        PREPROCESSED = /^[ \t]*!(?:include|startsub|endsub)/n
        MAX_DEPTH = 16
        private_constant :DIRECTIVE, :PREPROCESSED, :MAX_DEPTH

        module_function

        # @param source [String] PlantUML source
        # @param base_dir [String, nil] directory of the source; without it
        #   only include-path entries can be read
        # @param include_path [Array<String>, String, nil] extra roots
        # @return [String] the source with every include expanded
        # @raise [Error] a missing, refused or runaway include
        def expand(source, base_dir: nil, include_path: nil)
          return source unless source.b.match?(PREPROCESSED)

          finder = Finder.new(base_dir, include_path)
          lines = Blocks.strip_subs(Blocks.lines_of(source))
          walk(lines, finder, base_dir && File.expand_path(base_dir), 0)
            .join("\n")
        end

        def walk(lines, finder, dir, depth)
          lines.flat_map do |line|
            match = DIRECTIVE.match(line.strip)
            match ? include_lines(match, finder, dir, depth) : [line]
          end
        end

        def include_lines(match, finder, dir, depth)
          raise Error, "PlantUML include nests too deeply" if depth >= MAX_DEPTH

          name, selector = match[:spec].strip.split("!", 2)
          path = finder.locate(name, dir)
          kept = Blocks.pick(match[:kind], Blocks.lines_of(File.binread(path)),
                             name, selector)
          walk(Blocks.strip_subs(kept), finder, File.dirname(path), depth + 1)
        end
        private_class_method :walk, :include_lines
      end
    end
  end
end
