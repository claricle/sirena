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
          body = metadata_body(metadata)
          return {} if body.empty?

          # `@{}` is fine and means nothing; `@{` newline `}` is not, because
          # block YAML needs at least one entry. mermaid draws the first and
          # refuses the second.
          if body.strip.empty?
            raise Parser::ParseError, 'Empty metadata block.'
          end

          document = body.include?("\n") ? body : "{#{spaced(body)}}"
          mapping = yaml_mapping(document)
          reject_duplicates(mapping)

          mapping.children.each_slice(2).to_h do |key, value|
            [key.value, scalar(value)]
          end
        end

        # YAML's flow mapping needs a space after the colon; mermaid's
        # js-yaml does not, and `D@{shape:rounded}` appears in the corpus.
        # Quoted runs are copied through untouched so a colon inside a
        # label is left alone.
        def self.spaced(body)
          out = +''
          quote = nil

          body.each_char.with_index do |char, i|
            if quote
              quote = nil if char == quote
            elsif ['"', "'"].include?(char)
              quote = char
            elsif char == ':' && body[i + 1] !~ /[ \t]/
              out << ": "
              next
            end
            out << char
          end

          out
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
          keys = mapping.children.each_slice(2).map { |key, _| key.value }
          duplicate = keys.detect { |key| keys.count(key) > 1 }
          return unless duplicate

          raise Parser::ParseError, "Duplicate key: #{duplicate}."
        end

        # An absent or empty value is a no-op, which is what mermaid does
        # with `label:` and `label: ""` — the node keeps what it had.
        def self.scalar(value)
          return nil unless value.is_a?(Psych::Nodes::Scalar)
          return nil if value.value.empty?

          value.value
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

        def self.add_or_update_node(diagram, node_data)
          return unless node_data

          existing = diagram.find_node(node_data[:node_id])
          if existing
            # Update existing node - only update if we have non-default values
            existing.label = node_data[:label] if node_data[:label] && !node_data[:label].empty?
            # Only update shape if the new shape is not the default 'rect' or if existing is 'rect'
            if node_data[:shape_type] && node_data[:shape_type] != 'rect'
              existing.shape = node_data[:shape_type]
            end
            existing.classes = node_data[:classes] if node_data[:classes]
          else
            # Add new node
            node = create_node(node_data)
            diagram.nodes << node
          end
        end

        # Extract node data from parse tree
        def self.extract_node_data(node_hash)
          return nil unless node_hash

          node_id = node_hash[:node_id].to_s

          # Extract shape info if present
          if node_hash[:shape]
            shape_data = node_hash[:shape]
            delims = "#{shape_data[:open]}#{shape_data[:close]}"
            shape_type = SHAPE_MAP[delims] || 'rect'
            label = shape_data[:label]&.to_s&.strip || node_id
          else
            shape_type = 'rect'
            label = node_id
          end

          # `@{ shape: ..., label: ... }` wins over the bracket form, which
          # is what mermaid does when a node carries both.
          entries = metadata_entries(node_hash[:metadata])
          shape_type = metadata_shape(entries['shape']) || shape_type
          label = entries['label'] || label

          {
            node_id: node_id,
            shape_type: shape_type,
            label: label,
            classes: node_hash[:inline_class]&.to_s
          }
        end
      end
    end
  end
end