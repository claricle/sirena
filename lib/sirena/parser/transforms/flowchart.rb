# frozen_string_literal: true

require 'parslet'
require_relative '../base'
require_relative '../../diagram/flowchart'
require 'psych'
require_relative '../mermaid_shapes'

module Sirena
  module Parser
    module Transforms
      # Transform for converting flowchart parse trees to diagram models.
      #
      # Handles transformation of nodes, edges, subgraphs, and styling
      # directives from Parslet parse trees into Flowchart diagram objects.
      class Flowchart < Parslet::Transform
        # @raise [Parser::ParseError] on a shape name mermaid does not know
        def self.metadata_shape(name)
          return nil if name.nil?

          MERMAID_SHAPES.fetch(name) do
            raise Parser::ParseError, "No such shape: #{name}."
          end
        end

        # mermaid parses the body with js-yaml: a single-line body as a flow
        # mapping, a multiline one as block YAML. Psych does both, so the
        # rules fall out instead of being reimplemented in the grammar.
        #
        # @raise [Parser::ParseError] on YAML mermaid would also refuse
        def self.metadata_entries(metadata)
          body = break_quoted_newlines(metadata_body(metadata))
          return {} if body.empty?

          # `@{}` and `@{ }` are fine and mean nothing; `@{` newline `}` is
          # not, because block YAML needs at least one entry. mermaid draws
          # the first two and refuses the third.
          return {} if body.strip.empty? && !body.include?("\n")

          if body.strip.empty?
            raise Parser::ParseError, 'Empty metadata block.'
          end

          # Mermaid's own wrapping: a single-line body becomes a block
          # mapping between braces, a multiline one is used as written. It
          # does NOT normalise a missing space after a colon — `shape:rect`
          # is an unknown key there and the node keeps its default, so
          # inserting one made sirena honour something mermaid ignores.
          document = body.include?("\n") ? "#{body}\n" : "{\n#{body}\n}"
          entries(yaml_mapping(document))
        end

        # A newline inside a double-quoted value is a line break to
        # mermaid, which rewrites it before js-yaml ever sees it. Letting
        # YAML fold it turned `"one` newline `two"` into `one two`, where
        # mmdc renders `one<br/>two`.
        def self.break_quoted_newlines(body)
          body.gsub(/"[^"]*"/) { |run| run.gsub(/\n\s*/, '<br/>') }
        end

        def self.entries(mapping)
          reject_tags(mapping)
          reject_duplicates(mapping)
          reject_nested_anchors(mapping)

          resolve_mapping(mapping).filter_map do |key, value|
            next unless READ_KEYS.include?(key)

            usable = usable_value(key, value)
            [key, usable] if usable
          end.to_h
        end

        # Mermaid reads these two and ignores everything else, including a
        # merge key. Validating every entry refused `A@{ extra: true }`,
        # which mmdc draws.
        READ_KEYS = %w[shape label].freeze

        # The values are resolved off the AST rather than handed to a
        # loader. `Psych.safe_load` is not safe enough here: it still calls
        # any handler registered with `Psych.add_domain_type`, which is a
        # host-global list, and the handler's return value became the node
        # label. A diagram must not reach a materialiser at all.
        #
        # Doing it here also fixes the schema. Psych resolves `no` to false
        # and `2024-01-01` to a Date; mermaid parses with js-yaml's
        # JSON_SCHEMA, where both stay strings.
        def self.resolve_mapping(mapping)
          anchors = collect_anchors(mapping)

          mapping.children.each_slice(2).to_h do |key, value|
            [scalar_key(key), resolve(value, anchors, [])]
          end
        end

        # An Alias carries an anchor of its own, so collecting on that
        # alone recorded the alias over the node it points at and every
        # reference resolved to itself.
        def self.collect_anchors(node, found = {})
          found[node.anchor] = node if node.anchor &&
                                       !node.is_a?(Psych::Nodes::Alias)
          node.children.to_a.each { |child| collect_anchors(child, found) }
          found
        end

        # `open` is the chain of anchors currently being expanded. An alias
        # that reaches one of them is a cycle, and following it would
        # recurse until the stack gave out — the structural guard below
        # catches the shallow forms of this, not an anchor nested under a
        # sequence or one carried on the mapping itself.
        def self.resolve(node, anchors, open)
          if node.is_a?(Psych::Nodes::Alias)
            name = node.anchor
            raise Parser::ParseError, 'Circular anchor in metadata.' if
              open.include?(name)

            node = anchors.fetch(name) { missing_alias(node) }
            open += [name]
          end

          case node
          when Psych::Nodes::Scalar then json_scalar(node)
          when Psych::Nodes::Sequence
            node.children.map { |child| resolve(child, anchors, open) }
          else :unusable
          end
        end

        def self.missing_alias(node)
          raise Parser::ParseError, "No anchor for alias: #{node.anchor}."
        end

        # js-yaml's JSON_SCHEMA is what mermaid parses with, and it is
        # not JSON: the resolvers are YAML 1.1's. Each word has three
        # spellings, so `NULL` is null and mermaid keeps the old label
        # where a JSON reading would have set the string "NULL".
        JSON_WORDS = {
          'null' => nil, 'Null' => nil, 'NULL' => nil, '~' => nil,
          'true' => true, 'True' => true, 'TRUE' => true,
          'false' => false, 'False' => false, 'FALSE' => false
        }.freeze

        # Numbers carry a sign, group digits with `_`, and come in base
        # 2, 8 and 16 as well. JSON reads none of those, so `+1` and
        # `0x1F` were labels here and errors in mmdc.
        JSON_INT = /\A[-+]?(0b[01_]+|0o[0-7_]+|0x[0-9a-fA-F_]+|[0-9][0-9_]*)\z/

        # js-yaml's own float pattern. The sign is on two of the four
        # branches only: `-1.5` and `-.inf` resolve, `-.5` and `-.nan`
        # stay strings.
        JSON_FLOAT = /
          \A(?:
            [-+]?[0-9][0-9_]*(?:\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?
            |\.[0-9_]+(?:[eE][-+]?[0-9]+)?
            |[-+]?\.(?:inf|Inf|INF)
            |\.(?:nan|NaN|NAN)
          )\z
        /x

        STRING_TAG = 'tag:yaml.org,2002:str'

        def self.json_scalar(node)
          # An explicit `!!str` says what the value IS, so the implicit
          # rules do not run over it: mmdc draws `label: !!str 1` as "1".
          return node.value if node.quoted || node.tag == STRING_TAG

          return JSON_WORDS[node.value] if JSON_WORDS.key?(node.value)

          json_number(node.value) || node.value
        end

        # js-yaml tries the integer resolver before the float one, and
        # neither takes a trailing `_` — `1_` is a string. nil means the
        # scalar stays the string it was written as.
        def self.json_number(value)
          return nil if value.end_with?('_')

          digits = value.delete('_')
          return json_int(digits) if JSON_INT.match?(value)

          json_float(digits) if JSON_FLOAT.match?(value)
        end

        # Ruby reads the same three prefixes, but it also reads a bare
        # leading zero as octal, where js-yaml stays in base 10 — and
        # `Integer("08")` raises. So say the base for the plain form.
        def self.json_int(digits)
          digits.match?(/\A[-+]?0[box]/) ? Integer(digits) : Integer(digits, 10)
        end

        # The two words are named, not parsed: mermaid sees NaN, which is
        # falsy and skips the key, and Infinity, which is a number and is
        # refused like any other. `to_f` takes the rest and never raises,
        # so an odd but legal form like `1.` or `.5` stays a number
        # instead of throwing out of the parser.
        def self.json_float(digits)
          case digits.downcase
          when '.inf', '+.inf' then Float::INFINITY
          when '-.inf' then -Float::INFINITY
          when '.nan' then Float::NAN
          else digits.to_f
          end
        end

        # A tag routes the value through a materialiser, so only the ones
        # js-yaml's JSON schema can produce are allowed through. Everything
        # else — `!ruby/object:`, `!!omap`, a registered domain type — is
        # refused before anything is built.
        JSON_TAGS = %w[
          tag:yaml.org,2002:str tag:yaml.org,2002:int tag:yaml.org,2002:float
          tag:yaml.org,2002:bool tag:yaml.org,2002:null
          tag:yaml.org,2002:seq tag:yaml.org,2002:map
        ].freeze

        def self.reject_tags(node)
          if node.respond_to?(:tag) && node.tag && !JSON_TAGS.include?(node.tag)
            raise Parser::ParseError, "Unsupported tag: #{node.tag}."
          end

          node.children.to_a.each { |child| reject_tags(child) }
        end

        # An empty repeat captures as [], not as an empty slice.
        def self.metadata_body(metadata)
          return '' unless metadata.is_a?(Hash)

          value = metadata[:body]
          value.is_a?(Array) ? '' : value.to_s
        end

        def self.yaml_mapping(document)
          node = Psych.parse(document)&.children&.first
          raise Parser::ParseError, 'Malformed metadata.' unless
            node.is_a?(Psych::Nodes::Mapping)

          node
        rescue Psych::Exception
          raise Parser::ParseError, 'Malformed metadata.'
        end

        # mermaid raises on a duplicate key rather than taking the last.
        def self.reject_duplicates(mapping)
          keys = mapping.children.each_slice(2).map { |key, _| scalar_key(key) }
          duplicate = keys.detect { |key| keys.count(key) > 1 }
          return unless duplicate

          raise Parser::ParseError, "Duplicate key: #{duplicate}."
        end

        # A key that is not a plain scalar has no name to match against
        # `shape` or `label`, and calling `value` on a Sequence raised
        # NoMethodError before this guard.
        def self.scalar_key(node)
          node.is_a?(Psych::Nodes::Scalar) ? node.value : nil
        end

        # Mermaid tests the value for truth before using it, so `null`,
        # `false`, `0` and `""` are all no-ops rather than errors — the
        # node keeps what it had. Reading the raw AST made `shape: null`
        # a lookup for a shape called "null".
        #
        # A sequence renders its first element and nothing else: mmdc draws
        # `label: [one, two]` as `one`, and refuses a shape or a nested
        # sequence, where the value it reaches for is not a scalar.
        def self.usable_value(key, value)
          return nil unless truthy?(value)

          value = value.first if value.is_a?(Array) && key == 'label'
          return value if value.is_a?(String)

          raise Parser::ParseError, "Unusable #{key} in metadata."
        end

        # `null`, `false`, `0` and `""` are all falsy to mermaid, which
        # skips the key rather than failing on it. An empty collection is
        # NOT falsy in JavaScript, and mmdc does refuse `label: []`.
        def self.truthy?(value)
          return false if value.nil? || value == false
          return false if value.is_a?(Float) && value.nan?
          return false if value.is_a?(Numeric) && value.zero?
          return false if value.is_a?(String) && value.empty?
          return false if value == :unusable && false

          true
        end

        # An anchor holding an alias is how a few lines of YAML become
        # gigabytes. Mermaid has no use for the nesting, and a flat
        # `&s rounded` still resolves.
        def self.reject_nested_anchors(mapping)
          # An Alias node carries an anchor too, so selecting on that alone
          # flagged the plain `*s` reference the anchor exists to serve.
          anchored = mapping.children.select do |node|
            node.anchor && !node.is_a?(Psych::Nodes::Alias)
          end
          return if anchored.none? { |node| contains_alias?(node) }

          raise Parser::ParseError, 'Nested anchor in metadata.'
        end

        def self.contains_alias?(node)
          return true if node.is_a?(Psych::Nodes::Alias)

          node.children.to_a.any? { |child| contains_alias?(child) }
        end

        # Shape delimiter to type mapping
        SHAPE_MAP = {
          '[]' => 'rect',
          '()' => 'rounded',
          '([])' => 'stadium',
          '[[]]' => 'subroutine',
          '[()]' => 'cylindrical',
          '(())' => 'circle',
          '((()))' => 'double_circle',
          '>]' => 'asymmetric',
          '{}' => 'rhombus',
          '{{}}' => 'hexagon',
          '[//]' => 'parallelogram',
          '[\\\\]' => 'parallelogram_alt',
          '[/\\]' => 'trapezoid',
          '[\\/]' => 'trapezoid_alt'
        }.freeze

        # Arrow type mapping
        ARROW_MAP = {
          '-->' => 'arrow',
          '->' => 'arrow',
          '---' => 'line',
          '-.>' => 'dotted_arrow',
          '-.-' => 'dotted_arrow',
          '==>' => 'thick_arrow',
          '==' => 'thick_arrow'
        }.freeze

        # mermaid resolves the alias lexemes to a direction word before
        # anything reads one, so `graph <` lays out exactly like `graph RL`.
        # Measured against mmdc 11.12.0: `<` RL, `>` LR, `^` BT, `v` and
        # `BR` TB. Keeping the raw lexeme sent the three glyphs down the
        # default branch in the graph transform and drew them top-to-bottom.
        DIRECTION_ALIASES = {
          '<' => 'RL',
          '>' => 'LR',
          '^' => 'BT',
          'v' => 'TB',
          'BR' => 'TB'
        }.freeze

        # Direction value
        rule(dir_value: simple(:v)) { v.to_s }

        # Node ID
        rule(node_id: simple(:id)) { id.to_s }

        # Shape with label
        rule(
          shape: {
            open: simple(:o),
            label: simple(:l),
            close: simple(:c)
          }
        ) do
          delims = "#{o}#{c}"
          {
            shape_type: SHAPE_MAP[delims] || 'rect',
            label: l.to_s.strip
          }
        end

        # Handle empty labels
        rule(
          shape: {
            open: simple(:o),
            label: sequence(:_),
            close: simple(:c)
          }
        ) do
          delims = "#{o}#{c}"
          {
            shape_type: SHAPE_MAP[delims] || 'rect',
            label: ''
          }
        end

        # Arrow types
        rule(arrow: { plain: simple(:a) }) { a.to_s }
        rule(arrow: { dotted: simple(:a) }) { a.to_s }
        rule(arrow: { thick: simple(:a) }) { a.to_s }

        # Edge label
        rule(label: simple(:l)) { l.to_s.strip }
        rule(label: sequence(:l)) { l.join.strip }

        # Helper method to create nodes
        def self.create_node(node_data)
          Diagram::FlowchartNode.new.tap do |n|
            n.id = node_data[:node_id]
            n.label = node_data[:label] || node_data[:node_id]
            n.shape = node_data[:shape_type] || 'rect'
            n.classes = node_data[:classes] if node_data[:classes]
          end
        end

        # Helper method to create edges
        def self.create_edge(source_id, target_data, arrow_type, label = nil)
          Diagram::FlowchartEdge.new.tap do |e|
            e.source_id = source_id
            e.target_id = target_data[:node_id]
            e.arrow_type = ARROW_MAP[arrow_type] || 'arrow'
            # Convert Parslet::Slice to string before checking empty
            label_str = label.to_s if label
            e.label = label_str if label_str && !label_str.empty?
          end
        end

        # Process parsed diagram
        def self.apply(tree, diagram = nil)
          diagram ||= Diagram::Flowchart.new

          # Parse tree is an array: [header_element, *statement_elements]
          tree = [tree] unless tree.is_a?(Array)

          # Extract header (first element)
          header = tree.first
          if header && header.is_a?(Hash) && header[:direction]
            dir_value = header[:direction][:dir_value] || header[:direction]
            diagram.direction = canonical_direction(dir_value.to_s) if dir_value
          end

          # Process statements (remaining elements)
          statements = tree[1..-1] || []

          process_statements(diagram, statements)

          diagram
        end

        def self.canonical_direction(value)
          DIRECTION_ALIASES.fetch(value, value)
        end
        private_class_method :canonical_direction

        def self.process_statements(diagram, statements)
          statements.each do |stmt|
            next unless stmt.is_a?(Hash)

            if stmt[:node]
              # Node with edges
              process_node_edge_statement(diagram, stmt)
            elsif stmt[:node_id]
              # Standalone node
              node_data = { node_id: stmt[:node_id], shape_type: 'rect', label: stmt[:node_id] }
              add_or_update_node(diagram, node_data)
            elsif stmt[:subgraph_keyword]
              # The diagram model has no subgraph: no container, no title,
              # no cluster in any renderer. Flattening the body dropped
              # both and drew loose nodes where mermaid draws a cluster —
              # main refused the source outright, so accepting it here
              # would replace a refusal with a wrong picture.
              #
              # Guarded on the parsed marker, not the source text: a label
              # or an id containing "subgraph" never reaches this branch.
              raise Parser::ParseError,
                    'Flowchart subgraphs are not supported by the ' \
                    'diagram model.'
            elsif stmt[:style_keyword] || stmt[:classdef_keyword] ||
                  stmt[:class_keyword] || stmt[:click_keyword]
              # Styling directives (acknowledge but don't fully implement)
              # These are parsed but not processed into the model
            end
          end
        end

        def self.process_node_edge_statement(diagram, stmt)
          node_data = extract_node_data(stmt[:node])
          add_or_update_node(diagram, node_data)

          # Process edges if present
          edges = stmt[:edges]
          return unless edges

          edges = [edges] unless edges.is_a?(Array)
          source_id = node_data[:node_id]

          edges.each do |edge_data|
            next unless edge_data.is_a?(Hash)

            arrow_type = edge_data[:arrow].to_s
            label = edge_data[:label]
            target_data = edge_data[:target]

            next unless target_data

            # Extract and add target node
            target_node_data = extract_node_data(target_data)
            add_or_update_node(diagram, target_node_data)

            # Create edge
            edge = create_edge(source_id, target_node_data, arrow_type, label)
            diagram.edges << edge

            # For chaining, next edge source is current target
            source_id = target_node_data[:node_id]
          end
        end

        # A second mention of a node changes only what it actually says.
        # Treating an absent shape as `rect` and an absent label as the id
        # meant `A(keep)` followed by `A@{ shape: rect }` kept the round
        # shape and lost the label — mermaid does the opposite of both.
        def self.add_or_update_node(diagram, node_data)
          return unless node_data

          existing = diagram.find_node(node_data[:node_id])
          return diagram.nodes << create_node(node_data) unless existing

          existing.label = node_data[:label] if node_data[:label]
          existing.shape = node_data[:shape_type] if node_data[:shape_type]
          existing.classes = node_data[:classes] if node_data[:classes]
        end

        # Extract node data from parse tree
        def self.extract_node_data(node_hash)
          return nil unless node_hash

          node_id = node_hash[:node_id].to_s
          shape_type, label = bracket_shape(node_hash[:shape])

          # `@{ shape: ..., label: ... }` wins over the bracket form, which
          # is what mermaid does when a node carries both.
          entries = metadata_entries(node_hash[:metadata])

          {
            node_id: node_id,
            shape_type: metadata_shape(entries['shape']) || shape_type,
            label: entries['label'] || label,
            classes: node_hash[:inline_class]&.to_s
          }
        end

        # nil means the source said nothing, which is not the same as
        # saying `rect` or naming the node after itself. `create_node`
        # supplies the defaults, so only a real mention overwrites.
        def self.bracket_shape(shape_data)
          return [nil, nil] unless shape_data

          delims = "#{shape_data[:open]}#{shape_data[:close]}"
          label = shape_data[:label]
          # `A[ ]` is an EMPTY label, not an absent one: mmdc draws a node
          # with nothing in it, and treating it as absent named the node
          # after itself and kept an older label on a re-mention.
          [SHAPE_MAP[delims] || 'rect', label.nil? ? nil : label.to_s.strip]
        end
      end
    end
  end
end