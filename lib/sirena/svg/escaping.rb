# frozen_string_literal: true

module Sirena
  module Svg
    # XML escaping for everything Sirena writes into an SVG document.
    #
    # Nothing was escaped before this. A diagram label reading
    # `Alice<img src=` was emitted verbatim, which is malformed XML and, since
    # our SVG is embedded directly into Metanorma documents, lets diagram
    # source become markup in a rendered document.
    #
    # Two entry points because the rules differ. Text content only has to
    # protect the three characters that can start markup or an entity.
    # Attribute values additionally sit inside quotes, so both quote
    # characters have to go too.
    #
    # Each is a single pass over a character map rather than a chain of
    # replacements: escaping `&` after `<` would turn `&lt;` into `&amp;lt;`,
    # and a one-pass substitution cannot make that mistake regardless of the
    # order the map is written in.
    module Escaping
      TEXT = {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;'
      }.freeze

      ATTRIBUTE = TEXT.merge(
        '"' => '&quot;',
        "'" => '&apos;'
      ).freeze

      # Derived from the maps, never written out again. A hand-kept pattern
      # drifts: add a character to a map, forget the regex, and that character
      # silently stops being escaped while every test still passes.
      TEXT_PATTERN = Regexp.union(TEXT.keys).freeze
      ATTRIBUTE_PATTERN = Regexp.union(ATTRIBUTE.keys).freeze

      module_function

      # Escapes a value destined for element text content.
      #
      # @param value [Object] the value, stringified first
      # @return [String] the escaped text
      def escape_text(value)
        value.to_s.gsub(TEXT_PATTERN, TEXT)
      end

      # Escapes a value destined for a double-quoted attribute.
      #
      # @param value [Object] the value, stringified first
      # @return [String] the escaped value
      def escape_attribute(value)
        value.to_s.gsub(ATTRIBUTE_PATTERN, ATTRIBUTE)
      end

      # Renders one name/value pair as a leading-space XML attribute.
      #
      # This is the only place an attribute becomes text. Subclasses hand back
      # pairs rather than markup, so there is no second path to keep in sync.
      #
      # @param name [String] the attribute name
      # @param value [Object] the attribute value
      # @return [String] ` name="escaped"`
      def attribute(name, value)
        %( #{name}="#{escape_attribute(value)}")
      end

      # Renders name/value pairs, skipping any whose value is nil.
      #
      # @param pairs [Array<Array>] name/value pairs
      # @return [String] the concatenated attributes
      # @raise [ArgumentError] if handed anything but a pair
      def attributes(pairs)
        pairs.filter_map { |pair| render(pair) }.join
      end

      # @api private
      def render(pair)
        name, value = as_pair(pair)

        attribute(name, value) unless value.nil?
      end

      # The pairs contract is what makes the escaping boundary provable, so a
      # subclass still returning rendered markup has to fail loudly. Dropping
      # it silently would lose every attribute on that element.
      #
      # @api private
      def as_pair(pair)
        return pair if pair.is_a?(Array) && pair.size == 2

        raise ArgumentError,
              "expected a [name, value] pair, got #{pair.inspect}. " \
              'element_attributes returns pairs, not rendered markup.'
      end
    end
  end
end
