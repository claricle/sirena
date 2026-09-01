# frozen_string_literal: true

require 'strscan'

module Sirena
  # Separates a Mermaid source's preamble from its diagram body.
  #
  # Mermaid allows three things before the diagram keyword: a YAML
  # frontmatter block, `%%{init: ...}%%` directives, and `%%` comments.
  # Diagram type detection and every parser need the body without them.
  #
  # The three are split together rather than by three separate callers,
  # because `%%{` is also a valid `%%` comment opener — the ordering is part
  # of the lexing, not something a caller should have to know.
  #
  # @example
  #   Source.split("---\ntitle: T\n---\nflowchart LR\n  A-->B\n")
  #   # => { frontmatter: "title: T\n", directives: [], body: "flowchart LR\n..." }
  class Source
    # Malformed frontmatter is an error, not an absent title. Collapsing
    # the two meant sirena rendered `title: [` and a duplicated title,
    # both of which mermaid refuses.
    class MalformedFrontmatter < StandardError; end

    # A frontmatter block: `---` alone on a line, YAML, then `---` alone
    # again. The fences must be indented the SAME amount — mermaid accepts
    # a matching indent and rejects a mismatched one, and 44 corpus cases
    # are damaged in exactly that way (opener at column 0, closer indented).
    # At least one line has to sit between the fences: mermaid rejects an
    # empty block.
    FRONTMATTER = /\A([ \t]*)---[ \t]*\n(.+?)^\1---[ \t]*(?:\n|\z)/m

    # A byte order mark is a byte like any other to mermaid's frontmatter
    # regex, which is why a BOM in front of a fence costs the title. It is
    # not part of the diagram, though, so it comes off before anything is
    # detected.
    BOM = /\A﻿/

    # A comment line that is not the start of a directive. A bare `%%` is
    # one too: eight diagram types refuse it and fifteen render it, so the
    # split takes it either way and `Engine` asks the type.
    COMMENT = /\A[ \t]*%%(?!\{)[^\n]*(?:\n|\z)/

    # A `%%` with NOTHING after it on its line — not even a space. mmdc
    # renders `%% ` and `%%\t` in front of a flowchart and refuses a bare
    # `%%`, so the trailing whitespace is what makes it a comment.
    BARE_COMMENT = /\A[ \t]*%%(?:\n|\z)/

    # Mermaid's own directive scan, written out: `%%{`, a header word with
    # or without a colon, then a value that is either a bare word or
    # everything up to the first `}%%`.
    #
    # Two things about it are easy to get backwards and both were.
    #
    # The terminator is OPTIONAL. An unterminated directive still swallows
    # what it matched, so `%%{init: {}` alone on a line takes the diagram
    # with it and mmdc refuses the file. Requiring `}%%` instead left the
    # `%%{` sitting in the body, which reached the same verdict by luck and
    # the opposite one for `%%{init: x`, which mmdc renders.
    #
    # A bare-word value ends the directive where the word ends. Only the
    # `{...}` shape reaches forward for a `}%%`, which is why
    # `%%{init: {}` borrows one from further down the file and
    # `%%{init: x` does not.
    DIRECTIVE = /\A[ \t]*%%\{\s*(?:\w+\s*:|\w+)
                 \s*(?:\w+|(?:(?!\}%%).|\n)*)?\s*(?:\}%%)?/x

    # A `%%{` that scan will not take — no header word — is not a directive
    # to mermaid at all. It falls through to the comment pass, which eats
    # the whole LINE, `}%%` and all. That is the shape, and the shape
    # decides the verdict: `%%{}%%flowchart LR` loses the keyword with the
    # line, `%%{\n}%%` strands a `}%%` in front of the body, and mmdc
    # refuses both for all 23 types. Only a `%%{}%%` sitting alone on its
    # line costs the body nothing, and that one is type-dependent.
    DEGENERATE_DIRECTIVE = /\A[ \t]*%%\{[^\n]*(?:\n|\z)/
    BLANK_LINE = /\A[ \t]*\n/

    class << self
      # Splits a source into its preamble parts and its body.
      #
      # @param source [String] raw Mermaid source
      # @return [Hash] :frontmatter (String or nil), :directives (Array),
      #   :body (String), and :degenerate — the preamble items only some
      #   diagram types tolerate
      def split(source)
        scanner = StringScanner.new(normalize(source))

        # Frontmatter is read at the very start of the file and nowhere
        # else, so this runs before the BOM comes off and before any
        # comment is consumed. A fence anywhere behind them is still
        # lifted off the body, but its title is not read — see
        # `take_preamble`.
        frontmatter = take_frontmatter(scanner)
        scanner.skip(BOM)
        directives, degenerate = take_preamble(scanner)

        { frontmatter: frontmatter, directives: directives,
          body: scanner.rest, degenerate: degenerate }
      end

      # Reads the `title` out of a frontmatter block.
      #
      # @param frontmatter [String, nil] the YAML block, without its fences
      # @return [String, nil] the title mermaid would draw, or nil when it
      #   would draw none
      # @raise [MalformedFrontmatter] when mermaid's loader would refuse
      #   the document
      def title(frontmatter)
        return nil if frontmatter.nil? || frontmatter.strip.empty?

        Frontmatter.new(frontmatter).title
      end

      private

      # Mermaid treats a lone \r as a line ending too, and leaving them in
      # leaks carriage returns into labels and geometry downstream.
      def normalize(source)
        source.gsub(/\r\n?/, "\n")
      end

      def take_frontmatter(scanner)
        return nil unless scanner.scan(FRONTMATTER)

        dedent(scanner[2], scanner[1])
      end

      def dedent(yaml, indent)
        return yaml if indent.empty?

        yaml.gsub(/^#{Regexp.escape(indent)}/, '')
      end

      # A fence met here is not the first thing in the file, so mermaid
      # never reads it as frontmatter — it stays in the text and the
      # diagram's own parser meets it. Seventeen types choke on it and six
      # skip it, so the fence comes off the body either way and `Engine`
      # asks the type.
      #
      # Unless a bare `%%` or a headerless `%%{...}%%` came first. Those
      # are lines mermaid deletes whole, and deleting one leaves the fence
      # standing at the front of the file, where mermaid stops on it —
      # "Diagrams beginning with --- are not valid" — for every type, the
      # six lenient ones included. Leaving it in the body is what stops it
      # here: detection has nothing to match.
      #
      # Walks the preamble with a scanner rather than by handing a shorter
      # string to each round. Slicing the rest off per item copied the
      # whole remainder every time, which turned a long run of comments
      # quadratic — 64,000 of them took eleven seconds.
      def take_preamble(scanner)
        directives = []
        degenerate = []
        erased = false

        loop do
          next if scanner.skip(BLANK_LINE)

          if (directive = scanner.scan(DIRECTIVE))
            directives << directive.strip
          elsif scanner.skip(DEGENERATE_DIRECTIVE)
            degenerate << :directive
            erased = true
          elsif scanner.match?(COMMENT)
            if scanner.match?(BARE_COMMENT)
              degenerate << :comment
              erased = true
            end
            scanner.skip(COMMENT)
          elsif !erased && scanner.skip(FRONTMATTER)
            degenerate << :frontmatter
          else
            break
          end
        end

        [directives, degenerate.uniq]
      end
    end
  end
end

require_relative 'source/frontmatter'
