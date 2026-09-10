# frozen_string_literal: true

require_relative 'css_validity'

module Sirena
  module StyleCascade
    # The compiled, exact-case style map for one entity (the output of
    # `Resolver#resolve`), plus the two real read strategies mermaid
    # applies over it depending on how the element is drawn, and one more
    # independent tap for label color.
    #
    # `#attributed` and `#cascade` are genuinely different algorithms, not
    # two names for the same lookup — see each method's docs. Both are
    # ultimately reading the SAME map; which one a caller uses depends on
    # how the element renders (attributed-entity rough.js shape vs a bare
    # entity's `style="..."` browser cascade), not on the property name.
    class ResolvedStyles
      # @param exact_map [Hash{String => String}] the compiled, case-exact
      #   style map — insertion order matters (see `Resolver`).
      def initialize(exact_map)
        @exact_map = exact_map
      end

      # Models an ATTRIBUTED entity's box: mermaid draws it as a rough.js
      # shape whose fill/stroke/stroke-width are direct XML attributes read
      # from the compiled style map by EXACT lowercase key
      # (`userNodeOverrides` in mermaid's own bundle:
      # `s.get("fill")||themeDefault`) — no browser cascade on this path at
      # all, and no validation, ever. A hostile or malformed value reaches
      # the caller VERBATIM; this is what the D2 XSS-escaping contract
      # relies on (the caller passes it straight to the XML serializer,
      # which escapes it — this module must never substitute or drop it).
      #
      # @param property [String] exact-case property key, e.g. "fill"
      # @return [String, nil] the declared value, or nil if PROPERTY was
      #   never declared under this exact key (an empty declared value,
      #   e.g. `"fill:"`, also reads as nil — see `present`)
      def attributed(property)
        present(@exact_map[property])
      end

      # Models a BARE entity's box: mermaid renders it via an inline
      # `style="..."` SVG attribute, which a real browser resolves with
      # its own CSS cascade — case-insensitive property matching, the
      # LAST matching declaration wins, and a syntactically invalid value
      # is dropped as though never declared (the browser never applies
      # it). `currentColor` (any case) is then resolved against this same
      # box's ambient color, if one is declared.
      #
      # When nothing under PROPERTY validates, falls back to the raw
      # last-declared value rather than nil or a substituted default — a
      # hostile or malformed value must still reach the caller verbatim
      # (same D2 guarantee as `#attributed`, on this path).
      #
      # @param property [String] lowercase property name to resolve
      # @return [String, nil] the winning value, or nil if PROPERTY was
      #   never declared under any case
      def cascade(property)
        values = @exact_map.select { |key, _| key.downcase == property }.values
        value = last_valid_or_raw(values) { |v| CssValidity.valid?(property, v) }

        CssValidity::COLOR_PROPERTIES.include?(property) ? resolve_current_color(value) : value
      end

      # Models `isLabelStyle` in mermaid's own bundle: a declaration routes
      # to the entity's LABEL (its name/attribute text) only when the key
      # is the LITERAL lowercase string "color" — exact match, no case
      # folding. `COLOR:red` or `Color:red` are box styles instead (read
      # through `#cascade`), never the label's.
      #
      # @return [String, nil] the label's declared color, or nil
      def label_color
        present(@exact_map['color'])
      end

      private

      # An empty string is a validly-parsed but empty CSS value — the
      # browser drops an empty declaration (`fill:`) during cascade, and
      # mermaid's own override read is JS-falsy on it — so both treat it
      # as though the property was never declared.
      #
      # @return [String, nil] VALUE, or nil if it is nil or empty
      def present(value)
        value.nil? || value.empty? ? nil : value
      end

      # Picks the entry nearest the end of VALUES whose value passes the
      # block, treating an explicitly-cleared empty value as absent rather
      # than invalid. When nothing validates, falls back to the raw
      # last-declared value instead of nil — see `#cascade`'s docs for why.
      def last_valid_or_raw(values, &)
        present_values = values.filter_map { |value| present(value) }
        return nil if present_values.empty?

        present_values.reverse_each.find(&) || present_values.last
      end

      # The ambient colour a bare entity's box would compute `color` as:
      # every key matching "color" case-insensitively EXCEPT the literal
      # lowercase key (that one is the label's own color, excluded from
      # the box's ambient reading — see `#label_color`). Unlike
      # `#cascade`, an invalid ambient declaration is simply absent rather
      # than falling back to its raw text: `#resolve_current_color` below
      # already has a safe literal default (leave `currentColor` as
      # written, which a real browser resolves to black by CSS's own
      # initial value — no ambient color needed to reach that), so there
      # is no verbatim guarantee to uphold here.
      #
      # @return [String, nil] the winning ambient colour, or nil if none
      #   was validly declared
      def ambient_color
        values = @exact_map.select { |key, _| key != 'color' && key.downcase == 'color' }.values
        values.filter_map { |value| present(value) }
          .reverse_each.find { |value| CssValidity.color?(value) }
      end

      # `currentColor` on a bare entity's box resolves, in a real browser,
      # against that SAME element's `color` CSS property. Substitute the
      # concrete value now, since a standalone SVG has no browser cascade
      # left to resolve it at paint time.
      #
      # @param value [String, nil] the already cascade-resolved value
      # @return [String, nil] VALUE, or the ambient colour if VALUE is
      #   `currentColor` (any case) and one is validly declared
      def resolve_current_color(value)
        return value unless value&.downcase == 'currentcolor'

        ambient_color || value
      end
    end
  end
end
