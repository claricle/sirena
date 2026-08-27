# frozen_string_literal: true

require 'psych'
require_relative 'base'

module Sirena
  module Parser
    # The value mermaid ends up holding for a node's `@{ }` body.
    #
    # Mermaid hands the body to js-yaml under its JSON schema and reads two
    # keys off the result. js-yaml is not Psych: `no` stays a string there,
    # a forward alias is an error, and a mapping key is whatever JavaScript
    # makes of it. So the tree is composed here rather than loaded.
    #
    # Nothing calls `Psych.load`, `safe_load` or `to_ruby`. A loader applies
    # Ruby's type table instead of mermaid's, and it runs every converter
    # registered with `Psych.add_domain_type` — a host-global list any other
    # gem can add to. One of those built an object out of a node label.
    class MetadataYaml
      NON_SPECIFIC_TAG = '!'
      STR_TAG = 'tag:yaml.org,2002:str'
      INT_TAG = 'tag:yaml.org,2002:int'
      FLOAT_TAG = 'tag:yaml.org,2002:float'
      BOOL_TAG = 'tag:yaml.org,2002:bool'
      NULL_TAG = 'tag:yaml.org,2002:null'
      SEQ_TAG = 'tag:yaml.org,2002:seq'
      MAP_TAG = 'tag:yaml.org,2002:map'

      # What JavaScript writes when it needs a string for a plain object.
      OBJECT_STRING = '[object Object]'

      PLAIN_SCALAR = Psych::Nodes::Scalar::PLAIN

      # libyaml ends a line on NEL, LS or PS as well; js-yaml ends one on a
      # line feed or a carriage return and nothing else. A body carrying
      # one of the three cannot mean the same thing to both parsers, so it
      # is refused rather than read the wrong way round.
      FOREIGN_BREAK = /[\u0085\u2028\u2029]/

      # js-yaml drops a byte-order mark at the very start of the text and
      # leaves every other one alone; libyaml drops one at the start of any
      # line. A mark further in therefore hides a key from mermaid that
      # libyaml hands over as if it were plain — `@{` newline BOM
      # `label: hi }` keeps the node's old label in mmdc.
      BOM = "\uFEFF"

      # The transform has already turned every carriage return into a line
      # feed, the way mermaid does, and a foreign break is refused below.
      # So a line is whatever sits between two line feeds.
      YAML_BREAK = "\n"

      # js-yaml takes any 1.x document version and merely warns about the
      # ones it does not know; libyaml refuses everything but 1.1 and 1.2.
      # The version changes nothing either of them does with the tree, so
      # the number is levelled before parsing. Only the number: rewriting
      # the whole line dropped a trailing comment, and `%YAML 1.3 # note`
      # is a document mmdc draws. The number has to be a whole token, or
      # `%YAML 1.3#note` — which js-yaml reads as one unusable version and
      # refuses — became a levelled version with a comment after it.
      # A major other than 1, a second directive and anything else on the
      # line still fail in libyaml, as they do in js-yaml.
      DOCUMENT_VERSION = /^%YAML[ \t]+\K1\.\d+(?=[ \t]|$)/
      LEVELLED_VERSION = '1.2'

      # A directive only counts ahead of the document, next to the blank
      # lines and comments allowed to sit with it. Past that point a
      # `%YAML 1.3` at column 0 is ordinary text — a single-quoted value
      # carries on there — and levelling it rewrote a label mmdc draws
      # as written.
      DIRECTIVE_HEAD = /\A(?:%|[ \t]*(?:#|\z))/

      # js-yaml reads an anchor name up to whitespace or a flow indicator,
      # where libyaml stops at the first character an anchor may not hold.
      # `&a:b hi` is the anchor "a:b" holding "hi" there, and the anchor "a"
      # holding ":b hi" here, so the same source names a different label.
      # A tag may sit in front of the anchor, and is stepped over.
      ANCHOR_PROPERTY = /\A(?:!\S*[ \t]+)?&(?<name>[^\s,\[\]{}]*)/

      NULL_WORDS = %w[~ null Null NULL].freeze

      BOOL_WORDS = {
        'true' => true, 'True' => true, 'TRUE' => true,
        'false' => false, 'False' => false, 'FALSE' => false
      }.freeze

      # js-yaml's JSON_SCHEMA is what mermaid parses with, and it is not
      # JSON: the resolvers are YAML 1.1's. Each word has three spellings,
      # so `NULL` is null and mermaid keeps the old label where a JSON
      # reading would have set the string "NULL".
      JSON_WORDS = BOOL_WORDS.merge(
        NULL_WORDS.to_h { |word| [word, nil] }
      ).freeze

      # Numbers carry a sign, group digits with `_`, and come in base 2, 8
      # and 16 as well. JSON reads none of those, so `+1` and `0x1F` were
      # labels here and errors in mmdc.
      #
      # A leading zero is where js-yaml starts looking for a base
      # letter, so the character after it may not be `_`: `0_1` is not
      # an integer there and mmdc refuses `!!int 0_1`. A zero further
      # along is fine, and `00_1` is an integer to both.
      JSON_INT = %r{
        \A[-+]?(
          0b[01_]+ | 0o[0-7_]+ | 0x[0-9a-fA-F_]+
          | 0(?!_)[0-9_]* | [1-9][0-9_]*
        )\z
      }x

      # js-yaml's own float pattern. The sign is on two of the four
      # branches only: `-1.5` and `-.inf` resolve, `-.5` and `-.nan` stay
      # strings.
      JSON_FLOAT = /
        \A(?:
          [-+]?[0-9][0-9_]*(?:\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?
          |\.[0-9_]+(?:[eE][-+]?[0-9]+)?
          |[-+]?\.(?:inf|Inf|INF)
          |\.(?:nan|NaN|NAN)
        )\z
      /x

      # @raise [Parser::ParseError] on YAML mermaid would also refuse
      def self.value(document)
        new(document).value
      rescue SystemStackError
        # Walking the tree is recursive, so a body nested thousands deep
        # runs the stack out. mermaid blows its own browser stack on the
        # same source and refuses it, but SystemStackError is not a
        # StandardError and sailed past every caller on the way up.
        raise ParseError, 'Metadata nested too deeply.'
      end

      def initialize(document)
        @document = level_versions(document.delete_prefix(BOM))
        @lines = @document.split(YAML_BREAK, -1)
        @anchors = {}
      end

      # mermaid reads `doc.shape` off whatever `yaml.load` returns, so a
      # document that came back null throws there.
      def value
        composed = compose(root)
        raise ParseError, 'Empty metadata.' if composed.nil?

        composed
      end

      private

      def level_versions(text)
        lines = text.split(YAML_BREAK, -1)
        head = lines.take_while { |line| DIRECTIVE_HEAD.match?(line) }
        levelled = head.map do |line|
          line.sub(DOCUMENT_VERSION, LEVELLED_VERSION)
        end

        (levelled + lines.drop(head.size)).join(YAML_BREAK)
      end

      # `yaml.load` refuses a stream that is not exactly one document.
      def root
        reject_ambiguous_text
        documents = Psych.parse_stream(@document).children
        raise ParseError, 'Malformed metadata.' unless documents.one?

        documents.first.children.first
      rescue Psych::Exception
        raise ParseError, 'Malformed metadata.'
      end

      # Two characters the two parsers read differently, and neither leaves
      # a trace in the tree afterwards. The body is refused rather than
      # read the wrong way round.
      def reject_ambiguous_text
        raise ParseError, 'Unreadable line break.' if
          FOREIGN_BREAK.match?(@document)
        raise ParseError, 'Stray byte-order mark.' if
          @lines.any? { |line| line.start_with?(BOM) }
      end

      def compose(node)
        case node
        when Psych::Nodes::Alias then aliased(node)
        when Psych::Nodes::Scalar then scalar(node)
        when Psych::Nodes::Sequence then sequence(node)
        when Psych::Nodes::Mapping then mapping(node)
        end
      end

      # An anchor is only visible after the node that defines it, and a
      # redefined one resolves to whichever value came last before the
      # alias. Collecting the whole tree first gave both the wrong answer.
      def aliased(node)
        name = alias_name(node)
        @anchors.fetch(name) do
          raise ParseError, "No anchor for alias: #{name}."
        end
      end

      # js-yaml reads an alias name up to whitespace or a flow indicator,
      # where libyaml stops at the first character an anchor may not hold.
      # `*s: hi` is an alias named "s:" there, and mermaid reports it
      # undefined rather than reading the key.
      def alias_name(node)
        line = @lines[node.start_line]
        line[(node.start_column + 1)..][/\A[^\s,\[\]{}]*/]
      end

      def scalar(node)
        resolved = resolve_scalar(node)
        register_anchor(node, resolved)
        resolved
      end

      # The two parsers read the name differently, and libyaml leaves the
      # rest of it in the value, so the node cannot be read the way mermaid
      # reads it. It is refused instead.
      def register_anchor(node, value)
        name = node.anchor
        return unless name

        raise ParseError, "Ambiguous anchor: #{name}." unless
          js_anchor_name(node) == name

        @anchors[name] = value
      end

      def js_anchor_name(node)
        line = @lines[node.start_line]
        ANCHOR_PROPERTY.match(line[node.start_column..])&.[](:name)
      end

      def resolve_scalar(node)
        return empty_node(node.tag) if empty_node?(node)
        return tagged_scalar(node.tag, node.value) if explicit_tag?(node)
        return node.value if node.style != PLAIN_SCALAR ||
                             node.tag == NON_SPECIFIC_TAG

        implicit(node.value)
      end

      # A plain scalar with nothing in it is no content at all to js-yaml.
      # An empty string had to be written down. Psych reports `quoted` as
      # false for every tagged scalar, so the style is the only thing that
      # tells `!!seq` from `!!seq ""`.
      def empty_node?(node)
        node.style == PLAIN_SCALAR && node.value.empty?
      end

      def explicit_tag?(node)
        !node.tag.nil? && node.tag != NON_SPECIFIC_TAG
      end

      # A node with no content has no kind either, so js-yaml looks its tag
      # up in the whole table rather than the one for its kind, and hands
      # the constructor nothing. `!!seq` builds an empty array that way,
      # and `!!int` throws.
      def empty_node(tag)
        case tag
        when nil, NON_SPECIFIC_TAG, NULL_TAG then nil
        when STR_TAG then ''
        when SEQ_TAG then []
        when MAP_TAG then {}
        when INT_TAG, FLOAT_TAG, BOOL_TAG then unresolvable(tag)
        else unsupported(tag)
        end
      end

      # js-yaml runs the tag's own resolver over the value and refuses the
      # document when it says no, so `!!int nope` is an error rather than
      # the string it looks like.
      def tagged_scalar(tag, text)
        case tag
        when STR_TAG then text
        when INT_TAG then tagged_int(text)
        when FLOAT_TAG then tagged_float(text)
        when BOOL_TAG then BOOL_WORDS.fetch(text) { unresolvable(BOOL_TAG) }
        when NULL_TAG then tagged_null(text)
        else unsupported(tag)
        end
      end

      def tagged_int(text)
        json_int?(text) ? json_int(text.delete('_')) : unresolvable(INT_TAG)
      end

      def tagged_float(text)
        json_float?(text) ? json_float(text.delete('_')) : unresolvable(FLOAT_TAG)
      end

      def tagged_null(text)
        NULL_WORDS.include?(text) ? nil : unresolvable(NULL_TAG)
      end

      def implicit(text)
        return JSON_WORDS[text] if JSON_WORDS.key?(text)
        return json_int(text.delete('_')) if json_int?(text)
        return json_float(text.delete('_')) if json_float?(text)

        text
      end

      # js-yaml tries the integer resolver before the float one, and
      # neither takes a trailing `_` — `1_` is a string.
      def json_int?(text)
        !text.end_with?('_') && JSON_INT.match?(text)
      end

      def json_float?(text)
        !text.end_with?('_') && JSON_FLOAT.match?(text)
      end

      # Ruby reads the same three prefixes, but it also reads a bare
      # leading zero as octal, where js-yaml stays in base 10 — and
      # `Integer("08")` raises. So say the base for the plain form.
      def json_int(digits)
        digits.match?(/\A[-+]?0[box]/) ? Integer(digits) : Integer(digits, 10)
      end

      # The two words are named, not parsed: mermaid sees NaN, which is
      # falsy and skips the key, and Infinity, which is a number and is
      # refused like any other. `to_f` takes the rest and never raises, so
      # an odd but legal form like `1.` or `.5` stays a number instead of
      # throwing out of the parser.
      def json_float(digits)
        case digits.downcase
        when '.inf', '+.inf' then Float::INFINITY
        when '-.inf' then -Float::INFINITY
        when '.nan' then Float::NAN
        else digits.to_f
        end
      end

      def sequence(node)
        collection_tag(node, SEQ_TAG)
        list = []
        # Registered before the children are read, so `&s [*s]` resolves to
        # the array being built rather than running out of stack.
        register_anchor(node, list)
        node.children.each { |child| list << compose(child) }
        list
      end

      def mapping(node)
        collection_tag(node, MAP_TAG)
        reject_leading_property(node)
        pairs = {}
        register_anchor(node, pairs)
        node.children.each_slice(2) { |key, value| store(pairs, key, value) }
        pairs
      end

      # js-yaml composes the key, then the value, and only then complains
      # about a duplicate.
      def store(pairs, key, value)
        name = key_string(compose(key))
        composed = compose(value)
        raise ParseError, "Duplicate key: #{name}." if pairs.key?(name)

        pairs[name] = composed
      end

      # A collection takes its own tag or none. js-yaml looks a tag up in
      # the table for the node's kind, so `!!str [a, b]` finds nothing
      # there and is an unknown tag rather than a string.
      def collection_tag(node, own)
        return if node.tag.nil? || node.tag == NON_SPECIFIC_TAG ||
                  node.tag == own

        unsupported(node.tag)
      end

      # js-yaml stops allowing block collections the moment it reads a node
      # property followed by a space, so `&s shape: rounded` is a parse
      # error there — the anchor lands on a mapping it has not started
      # reading. libyaml takes it as an anchored key, so the mapping has to
      # be refused here instead.
      #
      # Only a property sitting exactly where the mapping starts does this.
      # An explicit `? &s shape` is two columns further in, and a flow
      # mapping's first key is past its brace, so both are left alone.
      def reject_leading_property(node)
        first = node.children.first
        # A body that is nothing but a comment composes as an empty flow
        # mapping, so there may be no first key to look at at all. mmdc
        # draws `A@{#}` with the label the node already had.
        return unless first&.anchor || first&.tag
        return unless first.start_line == node.start_line &&
                      first.start_column == node.start_column

        raise ParseError, 'Node property on a block mapping key.'
      end

      # JavaScript stores a mapping key as a string, so `1` and `1.0` are
      # one key and `[shape]` is the key `shape`. js-yaml writes any plain
      # object as "[object Object]" and refuses a nested array outright.
      def key_string(key)
        case key
        when Array then key.map { |item| key_element(item) }.join(',')
        when Hash then OBJECT_STRING
        else js_string(key)
        end
      end

      def key_element(item)
        case item
        when nil then '' # Array#join writes nothing at all for null.
        when Array then raise ParseError, 'Nested array in a metadata key.'
        when Hash then OBJECT_STRING
        else js_string(item)
        end
      end

      def js_string(value)
        case value
        when nil then 'null'
        when true, false then value.to_s
        when Numeric then js_number(value.to_f)
        else value
        end
      end

      # Every YAML number mermaid reads is a double, and JavaScript prints
      # one as the shortest decimal that reads back the same — plain while
      # the decimal exponent sits in (-6, 21] and in exponent form outside.
      # Ruby keeps a `.0`, turns to an exponent at 1e-5 and 1e16, and pads
      # the exponent to two digits. Keys are compared as text, so
      # 9007199254740992 and 9007199254740993 have to come out as one key.
      def js_number(number)
        return 'NaN' if number.nan?
        return number.negative? ? '-Infinity' : 'Infinity' if number.infinite?
        return '0' if number.zero?

        digits, point = decimal_parts(number.abs)
        "#{'-' if number.negative?}#{place_point(digits, point)}"
      end

      # `1.5` is the digits "15" with the point one in; `1e21` is "1" with
      # the point 22 in. Ruby's own `to_s` already gives the shortest
      # digits, so only where the point goes is left to work out.
      def decimal_parts(magnitude)
        mantissa, exponent = magnitude.to_s.split('e')
        whole, fraction = mantissa.split('.')
        digits = "#{whole}#{fraction}"
        significant = digits.sub(/\A0+/, '')
        point = whole.length - (digits.length - significant.length)
        [significant.sub(/0+\z/, ''), point + exponent.to_i]
      end

      # ECMA-262's Number::toString, in its own terms: `digits` runs from
      # the decimal point placed `point` digits in.
      def place_point(digits, point)
        return digits + ('0' * (point - digits.length)) if
          point.between?(digits.length, 21)
        return "#{digits[0, point]}.#{digits[point..]}" if
          point.positive? && point <= 21
        return "0.#{'0' * -point}#{digits}" if point > -6 && point <= 0

        exponential(digits, point - 1)
      end

      def exponential(digits, exponent)
        mantissa = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
        "#{mantissa}e#{exponent.negative? ? '-' : '+'}#{exponent.abs}"
      end

      def unsupported(tag)
        raise ParseError, "Unsupported tag: #{tag}."
      end

      def unresolvable(tag)
        raise ParseError, "Value does not fit #{tag}."
      end
    end

    private_constant :MetadataYaml
  end
end
