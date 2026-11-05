# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # The visibility icon PlantUML draws before a class member: a circle for
      # `+`, a square for `-`, a diamond for `#` and a triangle for `~`. A
      # field's icon is hollow and a method's is filled. `skinparam
      # classAttributeIconSize 0` turns the icons off and keeps the prefix
      # character in the text. Geometry is measured against PlantUML 1.2026.6.
      module MemberIcon
        extend self

        # The icon is centred this far from the box's left edge and the text
        # of a row that has one starts this far from it; any other row starts
        # at TEXT_PLAIN.
        CENTRE_INSET = 11.0
        TEXT_INSET = 20.0
        TEXT_PLAIN = 6.0
        # Offset of the icon's centre above the row's baseline.
        CENTRE_RISE = { circle: 3.79, square: 3.79, diamond: 4.79,
                        triangle: 4.79 }.freeze
        SHAPES = { public: :circle, private: :square, protected: :diamond,
                   package: :triangle }.freeze
        MARKS = { public: "+", private: "-", protected: "#",
                  package: "~" }.freeze
        DISABLED = /\Askinparam[ \t]+classAttributeIconSize[ \t]+0\z/i
        private_constant :CENTRE_RISE, :SHAPES, :MARKS, :DISABLED

        # @param directives [Array<String>] a diagram's directive lines
        # @return [Boolean] whether member icons are drawn
        def enabled?(directives)
          directives.none? { |line| DISABLED.match?(line) }
        end

        # @return [String] the written prefix character of a visibility
        def mark(visibility)
          MARKS.fetch(visibility, "")
        end

        # @param kinds [Array<Symbol>] each row's kind (:separator included)
        # @param visibilities [Array<Symbol, nil>] each row's visibility
        # @param enabled [Boolean] whether icons are drawn
        # @return [Array<Float, nil>] how far each row's text starts from the
        #   box's left edge: the whole of a field or method group is pushed
        #   in when any of its members carries an icon; nil for a separator
        def insets(kinds, visibilities, enabled)
          iconed = enabled ? iconed_kinds(kinds, visibilities) : []
          kinds.map do |kind|
            next if kind == :separator

            iconed.include?(kind) ? TEXT_INSET : TEXT_PLAIN
          end
        end

        def iconed_kinds(kinds, visibilities)
          kinds.zip(visibilities).filter_map do |kind, visibility|
            kind if SHAPES.key?(visibility)
          end
        end

        # @return [String] the row's text without the prefix an icon replaces
        def visible_text(content, visibility, enabled)
          return content unless enabled && SHAPES.key?(visibility)

          content.delete_prefix(mark(visibility))
        end

        # @param visibility [Symbol, nil]
        # @param kind [Symbol] :field or :method
        # @param left [Float] the box's left edge
        # @param baseline [Float] the member text's baseline
        # @return [Scene::Icon, nil] nil when the member has no visibility
        def at(visibility, kind, left, baseline)
          shape = SHAPES[visibility]
          return unless shape

          Scene::Icon.new(shape: shape.to_s, visibility: visibility.to_s,
                          filled: kind == :method, cx: left + CENTRE_INSET,
                          cy: baseline - CENTRE_RISE.fetch(shape))
        end
      end
    end
  end
end
