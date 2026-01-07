# frozen_string_literal: true

require 'parslet'
require_relative '../../diagram/flowchart'

module Sirena
  module Parser
    module Transforms
      # Transform for converting flowchart parse trees to diagram models.
      #
      # Handles transformation of nodes, edges, subgraphs, and styling
      # directives from Parslet parse trees into Flowchart diagram objects.
      class Flowchart < Parslet::Transform
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

        # Direction value
        rule(dir_value: simple(:v)) { v.to_s }

        # Node ID
        rule(node_id: simple(:id)) { id.to_s }
        rule(node_id: { string: simple(:s) }) { s.to_s }

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

        # Node with shape
        rule(
          node: {
            node_id: simple(:id),
            shape: subtree(:s)
          }
        ) do
          {
            node_id: id.to_s,
            shape_type: s[:shape_type] || 'rect',
            label: s[:label] || id.to_s
          }
        end

        # Node with shape and inline class
        rule(
          node: {
            node_id: simple(:id),
            inline_class: simple(:cls),
            shape: subtree(:s)
          }
        ) do
          {
            node_id: id.to_s,
            shape_type: s[:shape_type] || 'rect',
            label: s[:label] || id.to_s,
            classes: cls.to_s
          }
        end

        # Node without shape
        rule(node: { node_id: simple(:id) }) do
          {
            node_id: id.to_s,
            shape_type: 'rect',
            label: id.to_s
          }
        end

        # Node with inline class but no shape
        rule(
          node: {
            node_id: simple(:id),
            inline_class: simple(:cls)
          }
        ) do
          {
            node_id: id.to_s,
            shape_type: 'rect',
            label: id.to_s,
            classes: cls.to_s
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
            diagram.direction = dir_value.to_s if dir_value
          end

          # Process statements (remaining elements)
          statements = tree[1..-1] || []

          process_statements(diagram, statements)

          diagram
        end

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
              # Subgraph (acknowledge but don't fully implement for now)
              # Process subgraph statements recursively
              if stmt[:subgraph_statements]
                sub_stmts = stmt[:subgraph_statements]
                sub_stmts = [sub_stmts] unless sub_stmts.is_a?(Array)
                process_statements(diagram, sub_stmts)
              end
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