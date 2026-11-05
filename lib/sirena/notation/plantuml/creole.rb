# frozen_string_literal: true

require_relative "../../svg/text"

module Sirena
  module Notation
    module PlantUML
      # PlantUML's creole inline markup in a one-line label: `**bold**`,
      # `//italic//`, `__underline__`, `--strike--`, `~~wave~~` (drawn as an
      # underline), `""monospace""`, and the tags `<b>`, `<i>`, `<u>`, `<s>`,
      # `<w>`, `<color:red>`, `<size:18>` and `<back:..>` (the background is
      # not drawn; its text is kept). A marker with no partner stays literal,
      # and so does any tag it does not know, such as `<img>`. `<math>` and
      # `<latex>` are not typeset (no math engine is bundled): the formula
      # shows as monospace source, as PlantUML does without jlatexmath.
      # A `~` before a marker keeps the marker literal. `literal:` names
      # markers a caller wants kept as text even when paired.
      module Creole
        Run = Struct.new(:text, :style, keyword_init: true)

        TOGGLES = { "**" => :bold, "//" => :italic, "__" => :underline,
                    "--" => :strike, "~~" => :underline,
                    '""' => :mono }.freeze
        TAG_STYLES = { "b" => :bold, "i" => :italic, "u" => :underline,
                       "s" => :strike, "strike" => :strike,
                       "w" => :underline, "del" => :strike }.freeze
        PAIRED = %w[color size font].freeze
        IGNORED = %w[back].freeze
        TOKEN = %r{
          <(?<formula>math|latex)>(?<body>.*?)</\k<formula>>|
          \*\*|//|__|--|~~|""|~(?<escaped>\*\*|//|__|--|"")|
          <(?<close>/)?(?<tag>b|i|u|s|w|strike|del|color|size|back|font)
          (?:[:\s](?<arg>[^<>]*))?>
        }xi
        private_constant :TOGGLES, :TAG_STYLES, :PAIRED, :IGNORED, :TOKEN

        module_function

        # @param text [String] one label line
        # @param literal [Array<String>] toggle markers to keep as text
        # @return [Array<Run>] the line's styled pieces; one unstyled run
        #   when there is no markup
        def parse(text, literal: [])
          tokens = split(text.to_s)
          runs = runs_of(tokens, paired_toggles(tokens, literal))
          merge(runs.reject { |piece| piece.text.empty? })
        end

        def runs_of(tokens, paired)
          state = {}
          tokens.each_with_index.filter_map do |token, index|
            next run(token, state) unless token.is_a?(MatchData)

            styled(token, state, paired.include?(index))
          end
        end

        def styled(token, state, paired)
          return run(token[:escaped], state) if token[:escaped]
          return formula(token[:body], state) if token[:formula]

          run(token[0], state) unless apply(token, state, paired)
        end

        # Gives `element` the line's content: plain text when there is no
        # markup, one tspan per styled piece otherwise.
        #
        # @param element [Svg::Text]
        # @param text [String]
        def assign(element, text, literal: [])
          runs = parse(text, literal: literal)
          if runs.all? { |r| r.style.empty? }
            return element.content = runs.map(&:text).join
          end

          element.content = nil
          element.xml_space = "preserve"
          element.tspans = runs.map { |piece| tspan(piece) }
        end

        def split(text)
          pieces = []
          position = 0
          text.scan(TOKEN) do
            match = Regexp.last_match
            pieces << text[position...match.begin(0)]
            pieces << match
            position = match.end(0)
          end
          pieces << text[position..]
        end

        # Indexes of the toggle markers that have a partner: they pair up in
        # order, and a last odd one stays literal.
        def paired_toggles(tokens, literal)
          open = {}
          tokens.each_with_index.with_object(Set.new) do |(token, index), found|
            next unless toggle_token?(token) && !literal.include?(token[0])

            partner = open.delete(token[0])
            partner ? found << index << partner : open[token[0]] = index
          end
        end

        def toggle_token?(token)
          token.is_a?(MatchData) && !token[:escaped] &&
            TOGGLES.key?(token[0])
        end

        def apply(token, state, paired)
          text = token[0]
          if TOGGLES.key?(text)
            return unless paired

            toggle(state, TOGGLES.fetch(text))
          else
            tag(token, state)
          end
        end

        def toggle(state, style)
          state[style] ? state.delete(style) : state[style] = true
        end

        def tag(token, state)
          name = token[:tag].downcase
          return unless closer_known?(token, state, name)
          return true if IGNORED.include?(name)

          if PAIRED.include?(name)
            set_paired(state, name.to_sym, token)
          else
            style = TAG_STYLES.fetch(name)
            token[:close] ? state.delete(style) : state[style] = true
          end
          true
        end

        def set_paired(state, key, token)
          return state.delete(key) if token[:close]

          state[key] = token[:arg].to_s.strip
        end

        def closer_known?(token, state, name)
          return true unless token[:close]

          key = PAIRED.include?(name) ? name.to_sym : TAG_STYLES[name]
          IGNORED.include?(name) || state.key?(key)
        end

        def formula(text, state)
          Run.new(text: text, style: state.merge(mono: true))
        end

        def run(text, state)
          Run.new(text: text, style: state.dup)
        end

        def merge(runs)
          runs.each_with_object([]) do |piece, merged|
            if merged.last && merged.last.style == piece.style
              merged.last.text += piece.text
            else
              merged << piece
            end
          end
        end

        def tspan(piece)
          Svg::Tspan.new.tap do |node|
            node.content = piece.text
            decorate(node, piece.style)
          end
        end

        def decorate(node, style)
          node.font_weight = "bold" if style[:bold]
          node.font_style = "italic" if style[:italic]
          node.font_family = "monospace" if monospace?(style)
          node.text_decoration = decoration(style)
          decorate_size(node, style)
        end

        def monospace?(style)
          style[:mono] || style[:font]&.match?(/mono/i)
        end

        def decorate_size(node, style)
          node.fill = colour(style[:color]) if style[:color]
          node.font_size = style[:size] if style[:size]&.match?(/\A\d+\z/)
        end

        def decoration(style)
          words = []
          words << "underline" if style[:underline]
          words << "line-through" if style[:strike]
          words.join(" ") unless words.empty?
        end

        def colour(value)
          return value unless value.match?(/\A#?(?:\h{3}|\h{6})\z/)

          "##{value.delete_prefix('#')}"
        end
      end
    end
  end
end
