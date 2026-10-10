# frozen_string_literal: true

require "kramdown"

module Sirena
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
      AST_SINK = /\A[^_*]*?__[^_*]*?\*[^_*]*?(?=__)/
      UND_SINK = /\A[^_*]*?\*\*[^_*]*?_[^_*]*?(?=\*\*)/

      # Character and delimiter-run classification shared by the scanner.
      module Classification
        AST_CLASSIFICATIONS = {
          %i[punct space] => :close,
          %i[punct boundary] => :close,
          %i[word punct] => :close,
          %i[word space] => :close,
          %i[word boundary] => :close,
          %i[punct word] => :skip,
          %i[space word] => :skip,
          %i[space punct] => :skip,
          %i[punct punct] => :tight,
          %i[word word] => :tight,
        }.freeze
        UND_CLASSIFICATIONS = AST_CLASSIFICATIONS.merge(
          %i[word word] => :none,
        ).freeze

        def char_class(character)
          return :boundary if character.nil?
          return :space if character.match?(/\A[[:space:]]\z/)
          return :punct if character.match?(/\A[\p{P}\p{S}]\z/)

          :word
        end

        def alnum?(character)
          return false if character.nil?

          character.match?(/\A[\p{L}\p{N}]\z/)
        end

        # RDelim classification for a `*` candidate run.
        def classify_ast(prefix, suffix)
          AST_CLASSIFICATIONS.fetch([prefix, suffix], :none)
        end

        # RDelim classification for a `_` candidate run.
        def classify_und(prefix, suffix)
          UND_CLASSIFICATIONS.fetch([prefix, suffix], :none)
        end

        # Rejects a punctuation opener only after a word or marker.
        def open_gate_ok?(suffix_is_punct, previous_character)
          return true unless suffix_is_punct
          return true if previous_character.nil?
          return true if !%w[* _].include?(previous_character) &&
            %i[space punct].include?(char_class(previous_character))

          false
        end
      end

      # Stateful scan for the closer paired with one emphasis opener.
      class EmStrongScanner
        REJECT = Object.new.freeze

        def initialize(text, position, previous_character)
          @text = text
          @position = position
          @previous_character = previous_character
          @marker = text[position]
          @scan_position = marker_run_end(position)
          @opener_length = @scan_position - position
          @available = @opener_length
          @penalty = 0
        end

        def call
          return unless openable?

          skip_sink
          scan
        end

        private

        def openable?
          next_class = EmphasisSimulator.char_class(next_character)
          return false if %i[boundary space].include?(next_class)

          suffix_is_punct = next_class == :punct
          return false if intraword_underscore?(suffix_is_punct)

          EmphasisSimulator.open_gate_ok?(
            suffix_is_punct, @previous_character
          )
        end

        def next_character
          return if @scan_position >= @text.length

          @text[@scan_position]
        end

        def intraword_underscore?(suffix_is_punct)
          !suffix_is_punct && @marker == "_" &&
            EmphasisSimulator.alnum?(@previous_character)
        end

        def skip_sink
          sink = @marker == "*" ? AST_SINK : UND_SINK
          sink_match = sink.match(@text[@scan_position..])
          @scan_position += sink_match.end(0) if sink_match
        end

        def scan
          while (candidate = next_candidate)
            result = handle_candidate(*candidate)
            return nil if result.equal?(REJECT)
            return result if result
          end
          nil
        end

        def next_candidate
          closer_start = @text.index(@marker, @scan_position)
          return if closer_start.nil?

          closer_end = marker_run_end(closer_start)
          @scan_position = closer_end
          closer_length = closer_end - closer_start
          classification = classify(closer_start, closer_end)
          [classification, closer_start, closer_length]
        end

        def marker_run_end(start_position)
          run_end = start_position
          run_end += 1 while run_end < @text.length &&
              @text[run_end] == @marker
          run_end
        end

        def classify(closer_start, closer_end)
          prefix = EmphasisSimulator.char_class(@text[closer_start - 1])
          suffix = EmphasisSimulator.char_class(
            closer_end < @text.length ? @text[closer_end] : nil,
          )
          classifier = @marker == "*" ? :classify_ast : :classify_und
          EmphasisSimulator.public_send(classifier, prefix, suffix)
        end

        def handle_candidate(classification, closer_start, closer_length)
          case classification
          when :none
            nil
          when :skip
            skip(closer_length)
          when :tight
            handle_tight(closer_start, closer_length)
          else
            resolve(closer_start, closer_length)
          end
        end

        def skip(closer_length)
          @available += closer_length
          nil
        end

        def handle_tight(closer_start, closer_length)
          if odd_match?(closer_length)
            @penalty += closer_length
            return nil
          end
          return REJECT if @previous_character == @marker

          resolve(closer_start, closer_length)
        end

        def odd_match?(closer_length)
          (@opener_length % 3 != 0) &&
            ((@opener_length + closer_length) % 3).zero?
        end

        def resolve(closer_start, closer_length)
          result, @available = EmphasisSimulator.resolve_close(
            @available, closer_length, @penalty, @opener_length, closer_start
          )
          result
        end
      end

      # Builds the simulator's token tree while retaining source positions.
      class Tokenizer
        def initialize(text)
          @text = text
          @escapes = ::Kramdown::Parser::Kramdown::ESCAPED_CHARS
          @mask = text.gsub(@escapes) do
            "+" * ::Regexp.last_match(0).length
          end
          @tokens = []
          @position = 0
          @previous_character = nil
        end

        def call
          consume_next while @position < @text.length
          @tokens
        end

        private

        def consume_next
          if (escape_match = escaped_pair)
            consume_escape(escape_match)
          elsif (emphasis_match = matched_emphasis)
            consume_emphasis(emphasis_match)
          else
            consume_text
          end
        end

        def escaped_pair
          @text[@position, 2]&.match(@escapes)
        end

        def consume_escape(escape_match)
          EmphasisSimulator.append_text(@tokens, escape_match[1])
          @position += 2
          @previous_character = nil
        end

        def matched_emphasis
          character = @mask[@position]
          return unless EMPHASIS_MARKER.match?(character)

          EmphasisSimulator.try_em_strong(
            @mask, @position, @previous_character
          )
        end

        def consume_emphasis(emphasis_match)
          end_position, trim, strong = emphasis_match
          inner = @text[(@position + trim)...(end_position - trim)]
          @tokens << {
            type: strong ? :strong : :em,
            tokens: EmphasisSimulator.tokenize(inner),
          }
          @position = end_position
          @previous_character = nil
        end

        def consume_text
          start_position = @position
          @position += 1
          @position += 1 while plain_text_at_position?
          append_text(start_position)
          update_previous_character
        end

        def plain_text_at_position?
          return false if @position >= @text.length
          return false if EMPHASIS_MARKER.match?(@mask[@position])

          !escaped_pair
        end

        def append_text(start_position)
          run_text = @text[start_position...@position].gsub(@escapes) do
            ::Regexp.last_match(1)
          end
          EmphasisSimulator.append_text(@tokens, run_text)
        end

        def update_previous_character
          last_character = @text[@position - 1]
          @previous_character = last_character unless last_character == "_"
        end
      end

      # Produces and normalizes the styled runs returned by the simulator.
      module Runs
        def append_text(tokens, run_text)
          return if run_text.empty?

          if tokens.last && tokens.last[:type] == :text
            tokens.last[:text] << run_text
          else
            tokens << { type: :text, text: +run_text }
          end
        end

        def flatten(tokens, bold: false, italic: false, out: [])
          tokens.each do |token|
            flatten_token(token, bold: bold, italic: italic, out: out)
          end
          out
        end

        def coalesce_runs(runs)
          runs.each_with_object([]) do |run, coalesced|
            if same_style?(coalesced.last, run)
              coalesced[-1] = coalesced.last.with(
                text: coalesced.last.text + run.text,
              )
            else
              coalesced << run
            end
          end
        end

        private

        def flatten_token(token, bold:, italic:, out:)
          case token[:type]
          when :text
            out << Run.new(text: token[:text], bold: bold, italic: italic)
          when :em
            flatten(token[:tokens], bold: bold, italic: true, out: out)
          when :strong
            flatten(token[:tokens], bold: true, italic: italic, out: out)
          end
        end

        def same_style?(previous_run, run)
          previous_run && previous_run.bold == run.bold &&
            previous_run.italic == run.italic
        end
      end

      extend Classification
      extend Runs

      module_function

      def try_em_strong(text, position, previous_character)
        EmStrongScanner.new(text, position, previous_character).call
      end

      def resolve_close(
        available, closer_length, penalty, opener_length, closer_start
      )
        available -= closer_length
        return [nil, available] if available.positive?

        used = [closer_length, closer_length + available + penalty].min
        strong = ([opener_length, used].min % 2).zero?
        [[closer_start + used, strong ? 2 : 1, strong], available]
      end

      def tokenize(text)
        Tokenizer.new(text).call
      end

      def simulate(text)
        coalesce_runs(flatten(tokenize(text)))
      end

      private_constant :Classification, :EmStrongScanner, :Runs, :Tokenizer
    end
    private_constant :EmphasisSimulator
  end
end
