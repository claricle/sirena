# frozen_string_literal: true

require 'parslet'
require_relative '../base'
require_relative '../../diagram/flowchart'
require_relative '../metadata_yaml'
require_relative '../mermaid_shapes'

module Sirena
  module Parser
    module Transforms
      # Transform for converting flowchart parse trees to diagram models.
      #
      # Handles transformation of nodes, edges, subgraphs, and styling
      # directives from Parslet parse trees into Flowchart diagram objects.
      class Flowchart < Parslet::Transform
        # Two ways a name can fail, and they are not the same thing.
        # Mermaid does not know `nope`, and says so in words a corpus case
        # quotes. Mermaid does know `bang`, and draws it as a curved
        # outline sirena has no shape for — naming it a rectangle drew a
        # picture the source did not ask for, which is worse than saying no.
        #
        # @raise [Parser::ParseError] on a name sirena will not draw
        def self.metadata_shape(name)
          return nil if name.nil?

          MERMAID_SHAPES.fetch(name) do
            raise Parser::ParseError, unsupported_shape(name)
          end
        end

        def self.unsupported_shape(name)
          return "No such shape: #{name}." unless UNDRAWABLE_SHAPES.include?(name)

          "Shape not supported yet: #{name}."
        end
        private_class_method :unsupported_shape

        # mermaid parses the body with js-yaml: a single-line body as a flow
        # mapping, a multiline one as block YAML. Psych does both, so the
        # rules fall out instead of being reimplemented in the grammar.
        #
        # @raise [Parser::ParseError] on YAML mermaid would also refuse
        def self.metadata_entries(metadata)
          body = line_feeds(metadata_body(metadata))
          body = strip_metadata_comments(body)
          body = break_quoted_newlines(body)
          return {} if body.empty?

          # Mermaid's own wrapping: a single-line body becomes a flow
          # mapping between braces, a multiline one is used as written. It
          # does NOT normalise a missing space after a colon — `shape:rect`
          # is an unknown key there and the node keeps its default, so
          # inserting one made sirena honour something mermaid ignores.
          document = body.include?("\n") ? "#{body}\n" : "{\n#{body}\n}"
          entries(MetadataYaml.value(document))
        end

        # Mermaid turns every carriage return into a line feed before it
        # lexes anything, so a Windows line ending inside the block is an
        # ordinary newline by the time YAML sees it. Reading it as written
        # folded `"one` CR `two"` onto one line, left a `%YAML 1.3` CR
        # unlevelled, and took a body mermaid refuses.
        def self.line_feeds(body)
          body.gsub(/\r\n?/, "\n")
        end

        # Mermaid strips comments before lexing, so metadata never sees them.
        # `%%{` is a directive rather than a comment and stays, and a `%%`
        # with nothing after it is not a comment either.
        #
        # The body is a fragment cut from the middle of a line, so its own
        # first character is not the start of a line — only the newlines
        # inside it start one. Anchoring on `^` instead let the leading
        # whitespace run reach back past `@{` and eat the newline that
        # opened the block, which turned `A@{` nl `%% c` nl `}` into an
        # empty body sirena drew as a rectangle. mmdc refuses it, because
        # what is left after the comment goes is `A@{` nl `}`.
        def self.strip_metadata_comments(body)
          body.gsub(/(?<=\n)#{JS_SPACE}*%%(?!\{)[^\n]+\n?/o, '')
        end

        # A newline inside a double-quoted value is a line break to
        # mermaid, which rewrites it before js-yaml ever sees it. Letting
        # YAML fold it turned `"one` newline `two"` into `one two`, where
        # mmdc renders `one<br/>two`.
        def self.break_quoted_newlines(body)
          body.gsub(/"[^"]*"/) { |run| run.gsub(QUOTED_BREAK, '<br/>') }
        end

        # mermaid's lexer runs `/\n\s*/g` over the text between the quotes,
        # and that `\s` is JavaScript's. Ruby's is the five ASCII ones, so
        # a no-break space after the newline stayed in the label and mmdc
        # dropped it. The set below is JavaScript's exactly: it takes the
        # line and paragraph separators and the byte-order mark, and it
        # leaves the next-line character and the zero-width space alone.
        JS_SPACE = '[\t\n\v\f\r \u00a0\u1680\u2000-\u200a' \
                   '\u2028\u2029\u202f\u205f\u3000\ufeff]'

        QUOTED_BREAK = /\n#{JS_SPACE}*/

        private_constant :JS_SPACE, :QUOTED_BREAK

        # A key sirena does not read is left alone rather than validated:
        # `A@{ extra: true }` is a node mmdc draws, and a merge key is one
        # of those. A root that is not a mapping has neither key, and mmdc
        # draws the node untouched.
        #
        # Mermaid reads eight more keys off the document. Six of them
        # (`labelType`, `form`, `pos`, `w`, `h`, `constraint`) leave the
        # picture alone on their own, so ignoring them matches mmdc. Two do
        # not: `A@{ icon: "fa:bell" }` and `A@{ img: "x.png" }` each draw a
        # node with an empty label there, and a plain rectangle named `A`
        # here. Both are node kinds sirena does not have yet.
        def self.entries(document)
          return {} unless document.is_a?(Hash)

          READ_KEYS.filter_map do |key|
            usable = usable_value(key, document[key])
            [key, usable] if usable
          end.to_h
        end

        READ_KEYS = %w[shape label].freeze

        # An empty repeat captures as [], not as an empty slice.
        def self.metadata_body(metadata)
          return '' unless metadata.is_a?(Hash)

          value = metadata[:body]
          value.is_a?(Array) ? '' : value.to_s
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

          true
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
        def self.create_edge(source_id, target_data, link_shape, label = nil)
          Diagram::FlowchartEdge.new.tap do |e|
            e.source_id = source_id
            e.target_id = target_data[:node_id]
            e.arrow_type = canonical_arrow_type(link_shape)
            # Convert Parslet::Slice to string before checking empty
            label_str = label.to_s if label
            e.label = label_str if label_str && !label_str.empty?
          end
        end

        def self.canonical_arrow_type(link_shape)
          style, spelling = link_shape.first
          head = spelling.to_s.end_with?('>') ? 'arrow' : 'line'
          [style == :plain ? nil : style, head].compact.join('_')
        end
        private_class_method :canonical_arrow_type

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

            link_shape = edge_data[:arrow]
            label = edge_data[:label]
            target_data = edge_data[:target]

            next unless target_data

            # Extract and add target node
            target_node_data = extract_node_data(target_data)
            add_or_update_node(diagram, target_node_data)

            # Create edge
            edge = create_edge(source_id, target_node_data, link_shape, label)
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
