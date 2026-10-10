# frozen_string_literal: true

require "strscan"

module Sirena
  # Separates a Mermaid source's preamble from its diagram body.
  #
  # Mermaid allows three things before the diagram keyword: a YAML
  # frontmatter block, `%%{init: ...}%%` directives, and `%%` comments.
  # Split them together, not with three separate calls — `%%{` is also a
  # valid `%%` comment opener, so the ordering is part of the lexing.
  #
  # @example
  #   Source.split("---\ntitle: T\n---\nflowchart LR\n  A-->B\n")
  #   # => { frontmatter: "title: T\n", directives: [],
  #          body: "flowchart LR\n..." }
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
    BOM = /\A\uFEFF/

    # A comment line that is not the start of a directive. A bare `%%` is
    # one too: eight diagram types refuse it and fifteen render it, so the
    # split takes it either way and `Engine` asks the type.
    COMMENT = /\A[ \t]*%%(?!\{)[^\n]*(?:\n|\z)/

    # A `%%` with NOTHING after it on its line — not even a space. mmdc
    # renders `%% ` and `%%\t` in front of a flowchart and refuses a bare
    # `%%`, so the trailing whitespace is what makes it a comment.
    BARE_COMMENT = /\A[ \t]*%%(?:\n|\z)/

    # Mermaid's own directive scan: `%%{`, a header word with or without a
    # colon, then a value that is either a bare word or everything up to
    # the first `}%%`.
    #
    # Keep the terminator OPTIONAL: `%%{init: {}` alone on a line must
    # still swallow the diagram with it, matching mmdc's refusal.
    #
    # A value starting with a word character ends where that word ends
    # (`%%{init: x` takes "x"); every other shape (`{`, a quote, a bracket,
    # no value) reaches forward for `}%%` and takes the rest of the file
    # when there is none.
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
      # Frontmatter is read before the BOM comes off or comments are consumed;
      # a later fence can be removed from the body but does not provide title.
      def split(source)
        scanner = StringScanner.new(normalize(source))
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
      #
      # Never add a `strip.empty?` shortcut here: an empty-or-blank block is
      # `Frontmatter`'s own answer to give, and short-circuiting past it
      # makes this disagree with `Frontmatter.new(x).title` on invalid bytes.
      def title(frontmatter)
        return nil if frontmatter.nil?

        Frontmatter.new(frontmatter).title
      end

      private

      # Decodes to valid UTF-8 first, since every pattern below and in the
      # parsers raises on invalid bytes. Mermaid treats a lone \r as a line
      # ending too, and leaving them in leaks carriage returns into labels
      # and geometry downstream.
      def normalize(source)
        decode(source).gsub(/\r\n?/, "\n")
      end

      # mmdc reads its input as UTF-8 and draws U+FFFD for every invalid
      # run, so that is what every type gets: one valid UTF-8 string, before
      # any regexp or grammar sees it. `String#scrub` makes the same runs
      # as node's decoder.
      #
      # A string tagged BINARY or US-ASCII carries no encoding of its own
      # (`File.binread`, `$stdin.read` under `LANG=C`), so its bytes are read
      # as UTF-8, as mmdc reads a file. A string tagged with a real encoding
      # is transcoded instead; an encoding Ruby has no converter for (EUC-TW,
      # for one) falls back to the byte reading.
      def decode(source)
        case source.encoding
        when Encoding::UTF_8
          source.scrub
        when Encoding::BINARY, Encoding::US_ASCII
          source.dup.force_encoding(Encoding::UTF_8).scrub
        else
          transcode(source)
        end
      end

      # CESU-8 and the three UTF8-* carrier encodings come out of `encode`
      # tagged UTF-8 with their bytes unchecked, so the result is retagged
      # through its bytes to make `scrub` look at them.
      def transcode(source)
        source.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
          .b.force_encoding(Encoding::UTF_8).scrub
      rescue Encoding::ConverterNotFoundError
        source.b.force_encoding(Encoding::UTF_8).scrub
      end

      def take_frontmatter(scanner)
        return nil unless scanner.scan(FRONTMATTER)

        dedent(scanner[2], scanner[1])
      end

      def dedent(yaml, indent)
        return yaml if indent.empty?

        yaml.gsub(/^#{Regexp.escape(indent)}/, "")
      end

      # A fence met here is never frontmatter — it stays in the text for
      # the diagram's own parser, and `Engine` asks the type whether that
      # is fatal. Exception: once a bare `%%` or headerless `%%{...}%%` has
      # been erased, leave the fence in the body — mermaid deletes those
      # lines whole, which would otherwise leave the fence standing at the
      # front of the file where every type refuses it.
      #
      # Walk with a scanner instead of re-slicing the rest per item, which
      # is quadratic over a long run of comments.
      def take_preamble(scanner)
        directives = []
        degenerate = []
        erased = false
        while (state = consume_preamble_item(
          scanner, directives, degenerate, erased
        ))
          erased = state.first
        end
        [directives, degenerate.uniq]
      end

      def consume_preamble_item(scanner, directives, degenerate, erased)
        return [erased] if scanner.skip(BLANK_LINE)
        return take_directive(scanner, directives, erased) if
          scanner.match?(DIRECTIVE)

        return take_degenerate_directive(scanner, degenerate) if
          scanner.skip(DEGENERATE_DIRECTIVE)
        return take_comment(scanner, degenerate, erased) if
          scanner.match?(COMMENT)

        take_late_frontmatter_unless_erased(scanner, degenerate, erased)
      end

      def take_late_frontmatter_unless_erased(scanner, degenerate, erased)
        return if erased || !scanner.skip(FRONTMATTER)

        take_late_frontmatter(scanner, degenerate)
      end

      def take_directive(scanner, directives, erased)
        directives << scanner.scan(DIRECTIVE).strip
        [erased]
      end

      def take_degenerate_directive(_scanner, degenerate)
        degenerate << :directive
        [true]
      end

      def take_comment(scanner, degenerate, erased)
        bare = scanner.match?(BARE_COMMENT)
        degenerate << :comment if bare
        scanner.skip(COMMENT)
        [erased || bare]
      end

      def take_late_frontmatter(_scanner, degenerate)
        degenerate << :frontmatter
        [false]
      end
    end
  end
end

require_relative "source/frontmatter"
