# frozen_string_literal: true

require 'psych'

module Sirena
  class Source
    # Reads a frontmatter block the way mermaid reads it.
    #
    # Mermaid hands the block to a YAML loader and draws the JS string of
    # whatever came out under `title`. Both halves matter. The loader
    # refuses the WHOLE document over a repeated key or a tag it cannot
    # resolve, wherever they sit, so `x: !!float nope` is a rejection
    # even when the title is fine. And JS stringification is why
    # `title: 0` draws nothing while `title: [0, false, null]` draws
    # "0,false,".
    #
    # Psych parses to an AST rather than loading so alias resolution stays
    # under Sirena's control. Loading would expand aliases before the depth
    # and work bounds below could reject them.
    class Frontmatter
      # A plain scalar is resolved against these in order before falling
      # back to its own text. `title: True` draws "true" because of the
      # boolean row, and `title: 0x0` draws nothing because of the radix
      # one. Leading zeros stay decimal: mmdc draws `title: 017` as "17".
      NULL = /\A(?:~|null|Null|NULL)?\z/
      TRUE_TEXT = /\A(?:true|True|TRUE)\z/
      FALSE_TEXT = /\A(?:false|False|FALSE)\z/
      NAN = /\A\.(?:nan|NaN|NAN)\z/
      INFINITY = /\A([-+])?\.(?:inf|Inf|INF)\z/
      DECIMAL = /\A[-+]?[0-9][0-9_]*\z/

      # A radix prefix takes only the digits its base allows, so `0o9` and
      # `0b2` stay text — mmdc draws them as written. So does `0x_`:
      # grouping marks on their own are not a number.
      RADIX = /\A(?<sign>[-+])?0(?:
                x(?<hex>[0-9a-fA-F_]*[0-9a-fA-F][0-9a-fA-F_]*)
              | o(?<octal>[0-7_]*[0-7][0-7_]*)
              | b(?<binary>[01_]*[01][01_]*)
              )\z/x

      # A sign is allowed only when digits come before the point: mmdc
      # draws `.5` as 0.5 and leaves `+.5` and `-.5` as text.
      FLOAT = /\A(?:[-+]?[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9_]+)
              (?:[eE][-+]?[0-9]+)?\z/x

      RADICES = { hex: 16, octal: 8, binary: 2 }.freeze

      # The tags the loader knows. Anything else — `!!timestamp`,
      # `!!binary`, `!custom` — is a rejection, and so is a value that
      # will not resolve under the tag it carries.
      TAG = %r{\Atag:yaml\.org,2002:(null|bool|int|float|str|seq|map)\z}

      # What each scalar tag will hold, once the text has been resolved
      # the ordinary way. `!!float 1` is fine and draws "1"; `!!int 1.5`
      # is not. `!!str` is missing on purpose — it takes any text at all.
      SCALAR_TAGS = {
        'null' => [NilClass],
        'bool' => [TrueClass, FalseClass],
        'int' => [Integer],
        'float' => [Numeric]
      }.freeze

      # What a mapping stringifies to in JS, whatever it holds. Two
      # different mappings used as keys therefore collide.
      OBJECT = '[object Object]'

      # Both walks recurse, so both have to stop before the machine stack
      # does. A SystemStackError is not a StandardError, so it escapes
      # every rescue in the pipeline and takes the host down with it.
      #
      # The stack this runs on belongs to the caller, and a gem gets the
      # small ones: measured on Ruby 3.4, the walk gives out around 900
      # levels inside a Thread and around 500 inside a Fiber, where the
      # main thread reaches several thousand. So the bound is set for the
      # smallest of the three rather than for mermaid, which draws about
      # 1,400 levels before its own stack gives out. Nothing a person
      # writes comes near either number.
      MAX_NESTING = 256

      # Following an alias recurses twice per link, so the same reach
      # costs twice the frames.
      MAX_WALK = 512

      # Sirena is embedded in Metanorma, so a few hundred bytes must not buy
      # hundreds of thousands of allocations in its host process. Ten thousand
      # value-walk steps still permits unusually large human-written titles but
      # deliberately refuses some machine-generated titles mmdc renders, such
      # as its 531,441-element, roughly 1 MB alias expansion.
      MAX_VALUES = 10_000

      # @param yaml [String] the frontmatter block, without its fences
      def initialize(yaml)
        @yaml = yaml
        @anchors = {}
        @bindings = {}
      end

      # The title mermaid would draw for this block.
      #
      # @return [String, nil] the title, or nil when the block sets none
      #   and when mermaid would draw none
      # @raise [MalformedFrontmatter] when the document is malformed or
      #   exceeds Sirena's safety bounds
      def title
        @root = parse
        return nil unless @root

        budget = { remaining: MAX_VALUES }
        check(@root, budget)
        return nil unless @title_node

        drawn(value_of(@title_node, budget))
      end

      private

      # parse_stream rather than parse: `parse` hands back the FIRST
      # document and says nothing about the rest, so `title: T` followed
      # by `...` and a second document read as a plain title here while
      # mmdc exited nonzero.
      def parse
        stream = Psych.parse_stream(@yaml)
        reject_multiple if stream.children.length > 1

        stream.children.first&.children&.first
      rescue Psych::Exception, ArgumentError
        raise MalformedFrontmatter, 'Malformed frontmatter.'
      end

      def reject_multiple
        raise MalformedFrontmatter,
              'Frontmatter holds more than one YAML document.'
      end

      # The loader walks the document once, in order, and throws at the
      # first thing it cannot make sense of. An anchor registers as it
      # enters the node, which is why `a: &x [*x]` is allowed while an
      # alias that runs ahead of its anchor is not.
      def check(node, budget, depth = 0)
        return check_alias(node) if node.is_a?(Psych::Nodes::Alias)

        reject_depth if depth > MAX_NESTING
        @anchors[node.anchor] = node if node.anchor
        check_tag(node)
        return check_mapping(node, budget, depth) if node.is_a?(Psych::Nodes::Mapping)

        node.children.to_a.each { |child| check(child, budget, depth + 1) }
      end

      # An alias binds to the anchor standing where the alias sits, and
      # keeps that binding for good. The loader builds the value right
      # there, so a later `&x` cannot reach back into a list built
      # earlier: mmdc draws "one" for `a: &x one`, `b: &y [*x]`,
      # `c: &x two`, `title: *y`, where resolving `*x` at the end draws
      # "two".
      def check_alias(node)
        @bindings[node] = @anchors.fetch(node.anchor) do
          raise MalformedFrontmatter,
                "Frontmatter refers to an undefined anchor: #{node.anchor}."
        end
      end

      def reject_depth
        raise MalformedFrontmatter, 'Frontmatter is nested too deeply.'
      end

      # Keys collide when they spell the same JS property name. A
      # sequence key and the string that spells it are one key, and any
      # two mapping keys are.
      def check_mapping(mapping, budget, depth)
        seen = {}
        mapping.children.each_slice(2) do |key, value|
          check(key, budget, depth + 1)
          reject_nested_key if nested_sequence_key?(key)
          name = js_string(value_of(key, budget))
          reject_duplicate(name) if seen.key?(name)
          seen[name] = true
          check(value, budget, depth + 1)
          note_title(name, value) if mapping.equal?(@root)
        end
      end

      # Only the node is kept. Everything under it was bound as the walk
      # passed it, so the value can be built once the walk is over and
      # still read the anchors that stood where each alias sat.
      def note_title(name, value)
        return unless name == 'title'

        @title_node = value
      end

      def reject_duplicate(name)
        raise MalformedFrontmatter,
              "Duplicate key in frontmatter: #{name}."
      end

      # A sequence inside a key is the one shape the loader refuses
      # outright — "nested arrays are not supported inside keys". It looks
      # only at the key's own elements, so `? [{a: 1}]` and `? [~]` pass
      # and `? [[a]]` and `? [[]]` do not. The question is about the node,
      # not the value: `a: &x [*x]` then `? [*x]` holds a list that holds
      # itself, and the loader refuses that too.
      def nested_sequence_key?(key)
        node = resolved(key)
        return false unless node.is_a?(Psych::Nodes::Sequence)

        node.children.any? { |child| resolved(child).is_a?(Psych::Nodes::Sequence) }
      end

      # The node an alias stands for. An anchor never names an alias, so
      # one step is the whole chain.
      def resolved(node)
        node.is_a?(Psych::Nodes::Alias) ? @bindings.fetch(node) : node
      end

      def reject_nested_key
        raise MalformedFrontmatter,
              'Frontmatter nests a sequence inside a key.'
      end

      def check_tag(node)
        return if node.tag.nil?

        kind = node.tag[TAG, 1]
        return check_tag_fits(node, kind) if kind

        raise MalformedFrontmatter,
              "Frontmatter carries an unknown tag: #{node.tag}."
      end

      # A `!!seq` on a mapping is as wrong as a `!custom` anywhere, and a
      # scalar tag has to accept the text it sits on.
      def check_tag_fits(node, kind)
        return if fits?(node, kind)

        raise MalformedFrontmatter,
              "Frontmatter value does not fit #{node.tag}."
      end

      def fits?(node, kind)
        case node
        when Psych::Nodes::Sequence then kind == 'seq'
        when Psych::Nodes::Mapping then kind == 'map'
        else scalar_fits?(node, kind)
        end
      end

      # A collection tag on a scalar fits nothing, which is why
      # `title: !!seq x` is refused the same way `!!int nope` is.
      #
      # `!!float` has its own idea of a number and a radix prefix is not
      # in it: the loader takes `!!int 0x10` and refuses `!!float 0x10`,
      # though both resolve to 16 with no tag at all.
      def scalar_fits?(node, kind)
        return true if kind == 'str'
        return false if kind == 'float' && RADIX.match?(node.value)

        held = SCALAR_TAGS[kind]
        held&.any? { |type| resolve(node.value).is_a?(type) }
      end

      # The JS value the loader would build. A cycle comes back as null:
      # `a: &x [*x]` builds an array holding itself, and JS prints
      # nothing for the element that loops.
      def value_of(node, budget, open = [], depth = 0)
        reject_depth if depth > MAX_WALK
        consume_value(budget)

        case node
        when Psych::Nodes::Alias
          target = @bindings.fetch(node)
          return nil if open.include?(target)

          value_of(target, budget, open + [target], depth + 1)
        when Psych::Nodes::Scalar then scalar_value(node)
        when Psych::Nodes::Sequence
          node.children.map do |child|
            value_of(child, budget, open, depth + 1)
          end
        else OBJECT
        end
      end

      def consume_value(budget)
        reject_expansion unless budget[:remaining].positive?

        budget[:remaining] -= 1
      end

      def reject_expansion
        raise MalformedFrontmatter, 'Frontmatter expands to too many values.'
      end

      def scalar_value(node)
        return node.value if node.quoted
        return tagged_value(node) if node.tag

        resolve(node.value)
      end

      # `!!str` takes the text as it stands. Every other tag has already
      # been checked against what it can hold, so the ordinary resolution
      # is the value — `!!float 1` resolves to 1 and draws "1", which is
      # what mmdc draws.
      def tagged_value(node)
        return node.value if node.tag[TAG, 1] == 'str'

        resolve(node.value)
      end

      def resolve(text)
        return nil if NULL.match?(text)
        return true if TRUE_TEXT.match?(text)
        return false if FALSE_TEXT.match?(text)

        # Underscores are grouping marks, and a number cannot end on one.
        # That is the whole difference between `1_0`, which is ten, and
        # `1_`, which mmdc draws as the text "1_".
        return text if text.end_with?('_')

        number(text) || text
      end

      def number(text)
        return Float::NAN if NAN.match?(text)
        return infinity(text) if INFINITY.match?(text)
        return radix(text) if RADIX.match?(text)
        return text.delete('_').to_i if DECIMAL.match?(text)
        return text.delete('_').to_f if FLOAT.match?(text)

        nil
      end

      def infinity(text)
        text[INFINITY, 1] == '-' ? -Float::INFINITY : Float::INFINITY
      end

      def radix(text)
        found = text.match(RADIX)
        name, base = RADICES.detect { |key, _| found[key] }
        magnitude = Integer(found[name].delete('_'), base)
        found[:sign] == '-' ? -magnitude : magnitude
      end

      # Mermaid draws the title only when the value is truthy AND its
      # string is not empty. `title: 0` fails the first test, `title: []`
      # the second.
      def drawn(value)
        return nil unless truthy?(value)

        text = js_string(value)
        text.empty? ? nil : text
      end

      def truthy?(value)
        case value
        when nil, false then false
        when Float then !value.zero? && !value.nan?
        when Numeric then !value.zero?
        when String then !value.empty?
        else true
        end
      end

      def js_string(value)
        case value
        when nil then 'null'
        when Numeric then js_number(value)
        when Array
          value.map { |item| item.nil? ? '' : js_string(item) }.join(',')
        else value.to_s
        end
      end

      # Every YAML number reaches JS as a double, and JS prints one in
      # plain decimal only while the point sits within 21 digits of the
      # front and 6 of the back. Ruby switches to exponential far earlier,
      # at 1e16, and keeps a bignum exact that JS has already rounded. So
      # `title: 1e21` draws "1e+21", `title: 1e-5` draws "0.00001", and
      # `title: 9007199254740993` draws "9007199254740992".
      def js_number(value)
        double = value.to_f
        return double.to_s unless double.finite?
        return '0' if double.zero?

        digits, point = decompose(double)
        text = place(digits, point)
        double.negative? ? "-#{text}" : text
      end

      # Ruby's Float#to_s already gives the shortest digits that round
      # trip, and they are the same ones JS uses — only where the point
      # sits differs. So this pulls the two apart and `place` puts them
      # back together the way JS does.
      def decompose(double)
        mantissa, _, exponent = double.abs.to_s.partition('e')
        whole, _, fraction = mantissa.partition('.')
        combined = whole + fraction
        digits = combined.sub(/\A0+/, '')
        point = whole.length - (combined.length - digits.length) +
                exponent.to_i
        [digits.sub(/0+\z/, ''), point]
      end

      def place(digits, point)
        return exponential(digits, point) unless point > -6 && point <= 21
        return digits + ('0' * (point - digits.length)) if
          digits.length <= point
        return "0.#{'0' * -point}#{digits}" unless point.positive?

        "#{digits[0, point]}.#{digits[point..]}"
      end

      def exponential(digits, point)
        power = point - 1
        head = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
        "#{head}e#{power.negative? ? '-' : '+'}#{power.abs}"
      end
    end
  end
end
