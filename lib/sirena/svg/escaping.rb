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

      # XML 1.0 forbids these code points entirely: they have no escape, so a
      # document containing one is unparseable whatever you do to the rest.
      # Tab, newline and carriage return are the only C0 characters allowed.
      # A sequence label accepts any non-line-ending character
      # (grammars/sequence.rb:241), so a NUL in a diagram reached the output
      # and xmllint refused the SVG.
      FORBIDDEN = /[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD]/

      module_function

      # Removes characters XML cannot represent at all.
      #
      # Dropping rather than substituting: there is no legal escape for them,
      # and inventing a replacement character would put content in the document
      # that the author never wrote.
      def strip_forbidden(text)
        text.gsub(FORBIDDEN, '')
      end

      # Escapes a value destined for element text content.
      #
      # @param value [Object] the value, stringified first
      # @return [String] the escaped text
      def escape_text(value)
        strip_forbidden(value.to_s).gsub(TEXT_PATTERN, TEXT)
      end

      # Escapes a value destined for a double-quoted attribute.
      #
      # @param value [Object] the value, stringified first
      # @return [String] the escaped value
      def escape_attribute(value)
        strip_forbidden(value.to_s).gsub(ATTRIBUTE_PATTERN, ATTRIBUTE)
      end

      # An XML attribute name: a letter or underscore, then name characters.
      # Deliberately narrow — SVG attribute names are ASCII with hyphens and
      # the occasional colon.
      NAME = /\A[A-Za-z_][\w.:-]*\z/

      # Renders one name/value pair as a leading-space XML attribute.
      #
      # This is the only place an attribute becomes text. Subclasses hand back
      # pairs rather than markup, so there is no second path to keep in sync.
      #
      # The NAME check is not decoration: a pair whose name was
      # `x="safe" onload` produced a valid document with an extra injected
      # attribute, because only the value was ever escaped.
      #
      # @param name [String] the attribute name
      # @param value [Object] the attribute value
      # @return [String] ` name="escaped"`
      # @raise [ArgumentError] if the name is not a valid XML attribute name
      def attribute(name, value)
        return '' if blank?(value)

        unless name.to_s.match?(NAME)
          raise ArgumentError, "not a valid attribute name: #{name.inspect}"
        end

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

        attribute(name, value) unless blank?(value)
      end

      # lutaml-model leaves an unset attribute holding an UninitializedClass
      # sentinel rather than nil, and that object returns ITSELF from both
      # to_s and gsub. So it slipped past a nil check and past escaping, and
      # `Text.from_xml("<text>x</text>").to_xml` emitted
      # `fill-opacity="#<Lutaml::Model::UninitializedClass:0x...>"` — whose raw
      # `<` makes the document unparseable.
      #
      # Tested on to_s rather than on the sentinel's class name: any object
      # whose to_s does not return a String cannot be escaped, and matching a
      # class name by string would break the moment lutaml renames it.
      #
      # @api private
      def blank?(value)
        value.nil? || !value.to_s.is_a?(String)
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
