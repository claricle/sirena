# frozen_string_literal: true

require "kramdown"

module Sirena
  module Renderer
    module MarkdownText
      # A port of marked's REAL emStrong tokenizer (regex-driven scan, not
      # CommonMark's delimiter-stack algorithm, which real marked doesn't
      # implement). Used only by `unsafe_emphasis_divergence?` in
      # `markdown_text.rb` to predict marked's output for comparison.
      #
      # A naive "scan for the next same-marker run" model gets `"_**_**"`
      # wrong -- don't drop the `AST_SINK`/`UND_SINK` check below, which
      # swallows one embedded opposite-marker character after certain
      # `**...**`/`__...__` openings, matching marked's own RDelim regexes.
      module EmphasisSimulator
        # RDelimAst/RDelimUnd's own alternative 1 -- ported from the live
        # `emStrongRDelimAst`/`emStrongRDelimUnd` regex objects' first
        # alternative (captured directly from marked's runtime, not the
        # minified source string). See module comment above.
        AST_SINK = /\A[^_*]*?__[^_*]*?\*[^_*]*?(?=__)/
        UND_SINK = /\A[^_*]*?\*\*[^_*]*?_[^_*]*?(?=\*\*)/

        module_function

        def char_class(ch)
          return :boundary if ch.nil?
          return :space if ch.match?(/\A[[:space:]]\z/)
          return :punct if ch.match?(/\A[\p{P}\p{S}]\z/)

          :word
        end

        def alnum?(ch)
          return false if ch.nil?

          ch.match?(/\A[\p{L}\p{N}]\z/)
        end

        # RDelim classification for a `*` candidate run. Ported from
        # marked's `emStrongRDelimAst` regex (8 alternatives, excluding the
        # cross-underscore sink alternative handled separately by AST_SINK
        # above): :close counts against the opener's budget, :skip doesn't
        # count, :tight is subject to the multiple-of-3 odd-match rule,
        # :none is invisible to the scan.
        def classify_ast(prefix, suffix)
          ws_or_end = [:space, :boundary].include?(suffix)
          ps_or_end = [:punct, :space, :boundary].include?(suffix)
          return :close if prefix == :punct && ws_or_end
          return :close if prefix == :word && ps_or_end
          return :skip if [:punct, :space].include?(prefix) && suffix == :word
          return :skip if prefix == :space && suffix == :punct
          return :tight if prefix == :punct && suffix == :punct
          return :tight if prefix == :word && suffix == :word

          :none
        end

        # Same for `_`, ported from marked's `emStrongRDelimUnd` (7
        # alternatives, broader :skip case, no equivalent of Ast's alt8).
        def classify_und(prefix, suffix)
          ws_or_end = [:space, :boundary].include?(suffix)
          ps_or_end = [:punct, :space, :boundary].include?(suffix)
          return :close if prefix == :punct && ws_or_end
          return :close if prefix == :word && ps_or_end
          return :skip if [:punct, :space].include?(prefix) && suffix == :word
          return :skip if prefix == :space && suffix == :punct
          return :tight if prefix == :punct && suffix == :punct

          :none
        end

        # The second gate in real `emStrong`: rejects an open attempt only
        # when the opener's suffix is punctuation AND the preceding
        # character is real, non-blank, and not itself space/punct/marker.
        def open_gate_ok?(suffix_is_punct, prev_char)
          return true unless suffix_is_punct
          return true if prev_char.nil?
          return true if prev_char != "*" && prev_char != "_" && [:space, :punct].include?(char_class(prev_char))

          false
        end

        # Attempts one emStrong match starting at `text[pos]` (`*` or `_`),
        # given the tracked prevChar context. Returns
        # [end_position, trim, strong?], or nil (caller falls back to
        # literal-text consumption).
        def try_em_strong(text, pos, prev_char)
          c = text[pos]
          run_end = pos
          run_end += 1 while run_end < text.length && text[run_end] == c
          o = run_end - pos
          next_char = run_end < text.length ? text[run_end] : nil
          next_class = char_class(next_char)

          return nil if [:boundary, :space].include?(next_class)

          suffix_is_punct = next_class == :punct
          return nil if !suffix_is_punct && c == "_" && alnum?(prev_char)
          return nil unless open_gate_ok?(suffix_is_punct, prev_char)

          h = prev_char == c
          a = o
          p = 0
          scan_pos = run_end

          sink = c == "*" ? AST_SINK : UND_SINK
          sink_match = sink.match(text[scan_pos..])
          scan_pos += sink_match.end(0) if sink_match

          loop do
            next_start = text.index(c, scan_pos)
            return nil if next_start.nil?

            r_end = next_start
            r_end += 1 while r_end < text.length && text[r_end] == c
            u = r_end - next_start

            prefix_class = char_class(text[next_start - 1])
            suffix_class = char_class(r_end < text.length ? text[r_end] : nil)
            classification = c == "*" ? classify_ast(prefix_class, suffix_class) : classify_und(prefix_class, suffix_class)

            case classification
            when :none
              # not a delimiter run boundary here; keep scanning past it
            when :skip
              a += u
            when :tight
              if (o % 3 != 0) && ((o + u) % 3).zero?
                p += u
                scan_pos = r_end
                next
              end
              return nil if h

              result, a = resolve_close(a, u, p, o, next_start)
              return result if result

            else
              result, a = resolve_close(a, u, p, o, next_start)
              return result if result

            end
            scan_pos = r_end
          end
        end

        # Shared "resolve or keep scanning" step for a `:tight`/`:close`
        # candidate: returns `[match, updated_a]` where `match` is the
        # emStrong result once the opener's budget is exhausted, or `[nil,
        # updated_a]` to keep scanning from `r_end`.
        def resolve_close(a, u, p, o, next_start)
          a -= u
          return [nil, a] if a.positive?

          u_used = [u, u + a + p].min
          strong = ([o, u_used].min % 2).zero?
          [[next_start + u_used, strong ? 2 : 1, strong], a]
        end

        def append_text(tokens, run_text)
          return if run_text.empty?

          if tokens.last && tokens.last[:type] == :text
            tokens.last[:text] << run_text
          else
            tokens << { type: :text, text: +run_text }
          end
        end

        # Tokenizes one segment into {type: :text, text:} /
        # {type: :em/:strong, tokens: [...]} nodes.
        #
        # Classification runs on `masked` (escapes replaced by same-length
        # `+`), never on `text` -- an escaped `*`/`_` must never open,
        # close, or extend a run. Output text always comes from `text`,
        # with escapes resolved.
        #
        # `prev_char` resets to nil after an escape token or emStrong
        # match; only a plain literal-text run updates it.
        def tokenize(text)
          escaped_chars = ::Kramdown::Parser::Kramdown::ESCAPED_CHARS
          masked = text.gsub(escaped_chars) { "+" * ::Regexp.last_match(0).length }
          tokens = []
          pos = 0
          prev_char = nil

          while pos < text.length
            pair = text[pos, 2]
            pair_match = pair&.match(escaped_chars)
            if pair_match
              append_text(tokens, pair_match[1])
              pos += 2
              prev_char = nil
              next
            end

            ch = masked[pos]
            match = MarkdownText::EMPHASIS_MARKER.match?(ch) ? try_em_strong(masked, pos, prev_char) : nil

            if match
              end_pos, trim, strong = match
              content = text[(pos + trim)...(end_pos - trim)]
              tokens << { type: strong ? :strong : :em, tokens: tokenize(content) }
              pos = end_pos
              prev_char = nil
              next
            end

            start = pos
            pos += 1
            while pos < text.length
              break if MarkdownText::EMPHASIS_MARKER.match?(masked[pos])

              next_pair = text[pos, 2]
              break if next_pair&.match?(escaped_chars)

              pos += 1
            end
            run_text = text[start...pos].gsub(escaped_chars) { ::Regexp.last_match(1) }
            append_text(tokens, run_text)

            last_ch = text[pos - 1]
            prev_char = last_ch unless last_ch == "_"
          end

          tokens
        end

        def flatten(tokens, bold: false, italic: false, out: [])
          tokens.each do |tok|
            case tok[:type]
            when :text
              out << MarkdownText::Run.new(text: tok[:text], bold: bold, italic: italic)
            when :em
              flatten(tok[:tokens], bold: bold, italic: true, out: out)
            when :strong
              flatten(tok[:tokens], bold: true, italic: italic, out: out)
            end
          end
          out
        end

        # Coalesces adjacent same-style runs into one -- needed both by
        # `simulate` below and by `unsafe_emphasis_divergence?` for the
        # kramdown-tree side, so the two are compared on equal terms
        # (`flatten_runs` alone can leave adjacent same-style runs
        # un-merged where kramdown's tree happens to split them across
        # sibling text nodes).
        def coalesce_runs(runs)
          out = []
          runs.each do |run|
            if out.last && out.last.bold == run.bold && out.last.italic == run.italic
              out[-1] = out.last.with(text: out.last.text + run.text)
            else
              out << run
            end
          end
          out
        end

        def simulate(text)
          coalesce_runs(flatten(tokenize(text)))
        end
      end
      private_constant :EmphasisSimulator
    end
  end
end
