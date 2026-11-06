# frozen_string_literal: true

require_relative "../../svg/text"
require_relative "creole_icons"

module Sirena
  module Notation
    module PlantUML
      # PlantUML's creole inline markup in a one-line label: `**bold**`,
      # `//italic//`, `__underline__`, `--strike--`, `~~wave~~` (drawn as an
      # underline), `""monospace""`, and the tags `<b>`, `<i>`, `<u>`, `<s>`,
      # `<w>`, `<color:red>`, `<size:18>` and `<back:..>` (the background is
      # not drawn; its text is kept). `<s:red>` and `<u:red>` keep their
      # colour in the run for a caller that draws the line itself. A marker
      # with no partner stays literal, and so does any tag it does not know.
      # `<img..>` is never fetched: PlantUML prints "(Cannot decode)" in
      # monospace for an image it cannot load, and so does this. `<math>` and
      # `<latex>` are not typeset (no math engine is bundled): the formula
      # shows as monospace source, as PlantUML does without jlatexmath.
      # A `~` before a marker keeps the marker literal. `literal:` names
      # markers a caller wants kept as text even when paired.
      #
      # With `inline: true` (a data diagram's cell) `<&icon>` (an Open Iconic
      # glyph) and `<:emoji:>` become runs of non-breaking spaces as wide as
      # the picture, which the caller draws over; `<back:..>` is kept in the
      # run for the caller to paint.
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
        LINE_TAGS = %w[s u].freeze
        # Spaces held for a picture: 3 for an icon, 5 for an emoji.
        PICTURE_ROOM = { icon: 3, emoji: 5 }.freeze
        TOKEN = %r{
          <(?<formula>math|latex)>(?<body>.*?)</\k<formula>>|
          (?<image><img[:\s][^<>]*>)|
          \*\*|//|__|--|~~|""|~(?<escaped>\*\*|//|__|--|"")|
          <(?<close>/)?(?<tag>b|i|u|s|w|strike|del|color|size|back|font)
          (?:[:\s](?<arg>[^<>]*))?>
        }xi
        PICTURE = "|<&(?<icon>[\\w-]+)>|<:(?<emoji>[\\w-]+):>"
        UNDECODED_IMAGE = "(Cannot decode)"
        INLINE_TOKEN = Regexp.new(TOKEN.source + PICTURE, TOKEN.options)
        private_constant :TOGGLES, :TAG_STYLES, :PAIRED, :IGNORED, :TOKEN,
                         :LINE_TAGS, :PICTURE_ROOM, :PICTURE, :UNDECODED_IMAGE,
                         :INLINE_TOKEN

        module_function

        # @param text [String] one label line
        # @param literal [Array<String>] toggle markers to keep as text
        # @return [Array<Run>] the line's styled pieces; one unstyled run
        #   when there is no markup
        def parse(text, literal: [], inline: false)
          tokens = split(text.to_s, inline)
          runs = runs_of(tokens, paired_toggles(tokens, literal), inline)
          merge(runs.reject { |piece| piece.text.empty? })
        end

        def runs_of(tokens, paired, inline)
          state = {}
          tokens.each_with_index.filter_map do |token, index|
            next run(token, state) unless token.is_a?(MatchData)

            styled(token, state, paired.include?(index), inline)
          end
        end

        # @param text [String] one label line
        # @return [String] the line as drawn: the markup is gone, its text
        #   stays
        def plain(text)
          parse(text).map(&:text).join
        end

        def styled(token, state, paired, inline)
          return run(token[:escaped], state) if token[:escaped]
          return formula(token[:body], state) if token[:formula]
          return picture(token, state) if picture?(token)
          return undecoded_image(state) if token[:image]

          run(token[0], state) unless apply(token, state, paired, inline)
        end

        # A `<&icon>` of a set PlantUML ships, or any `<:emoji:>`. Any other
        # icon name falls to `apply`, which leaves it literal.
        def picture?(token)
          token.names.include?("icon") &&
            (token[:emoji] || Icons.known?(token[:icon]))
        end

        def undecoded_image(state)
          Run.new(text: UNDECODED_IMAGE, style: state.merge(mono: true))
        end

        def picture(token, state)
          kind = token[:emoji] ? :emoji : :icon
          Run.new(text: "\u00A0" * PICTURE_ROOM.fetch(kind),
                  style: state.merge(kind => token[kind]))
        end

        # Gives `element` the line's content: plain text when there is no
        # markup, one tspan per styled piece otherwise.
        #
        # @param element [Svg::Text]
        # @param text [String]
        def assign(element, text, literal: [], inline: false)
          runs = parse(text, literal: literal, inline: inline)
          if runs.all? { |r| r.style.empty? }
            return element.content = runs.map(&:text).join
          end

          element.content = nil
          element.xml_space = "preserve"
          element.tspans = runs.map { |piece| tspan(piece, inline: inline) }
        end

        def split(text, inline)
          pieces = []
          position = 0
          text.scan(inline ? INLINE_TOKEN : TOKEN) do
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

        def apply(token, state, paired, inline)
          text = token[0]
          if TOGGLES.key?(text)
            return unless paired

            toggle(state, TOGGLES.fetch(text))
          else
            tag(token, state, inline)
          end
        end

        def toggle(state, style)
          state[style] ? state.delete(style) : state[style] = true
        end

        def tag(token, state, inline)
          return unless token[:tag]

          name = token[:tag].downcase
          return unless closer_known?(token, state, name)

          mark(token, state, name, inline)
          true
        end

        def mark(token, state, name, inline)
          if PAIRED.include?(name) || (inline && name == "back")
            set_paired(state, name.to_sym, token)
          elsif !IGNORED.include?(name)
            set_style(state, name, token)
          end
        end

        def set_style(state, name, token)
          style = TAG_STYLES.fetch(name)
          if token[:close]
            state.delete(style)
            state.delete(:"#{style}_colour")
          else
            state[style] = true
            colour = token[:arg].to_s.strip
            return if colour.empty? || !LINE_TAGS.include?(name)

            state[:"#{style}_colour"] = colour
          end
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

        def tspan(piece, inline: false)
          Svg::Tspan.new.tap do |node|
            node.content = piece.text
            decorate(node, piece.style, inline: inline)
          end
        end

        def decorate(node, style, inline: false)
          node.font_weight = "bold" if style[:bold]
          node.font_style = "italic" if style[:italic]
          node.font_family = "monospace" if monospace?(style)
          node.text_decoration = decoration(style, inline: inline)
          decorate_size(node, style)
        end

        def monospace?(style)
          style[:mono] || style[:font]&.match?(/mono/i)
        end

        def decorate_size(node, style)
          node.fill = colour(style[:color]) if style[:color]
          node.font_size = style[:size] if style[:size]&.match?(/\A\d+\z/)
        end

        # A coloured line is drawn by the caller when `inline`, so the text
        # carries no black one beneath it.
        def decoration(style, inline: false)
          words = []
          words << "underline" if drawn?(style, :underline, inline)
          words << "line-through" if drawn?(style, :strike, inline)
          words.join(" ") unless words.empty?
        end

        def drawn?(style, key, inline)
          style[key] && !(inline && style[:"#{key}_colour"])
        end

        def colour(value)
          return value unless value.match?(/\A#?(?:\h{3}|\h{6})\z/)

          "##{value.delete_prefix('#')}"
        end
      end
    end
  end
end
