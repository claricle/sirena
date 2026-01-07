# frozen_string_literal: true

require 'parslet'
require_relative '../../diagram/block'

module Sirena
  module Parser
    module Transforms
      # Transform for converting block diagram parse trees to diagram models.
      #
      # Handles transformation of blocks, compound blocks, connections, and
      # styling directives from Parslet parse trees into BlockDiagram objects.
      class Block < Parslet::Transform
        # Shape delimiter to type mapping
        SHAPE_MAP = {
          '[]' => 'rect',
          '(())' => 'circle'
        }.freeze

        # Arrow type mapping
        ARROW_MAP = {
          '-->' => 'arrow',
          '---' => 'line'
        }.freeze

        # Block ID
        rule(block_id: simple(:id)) { id.to_s }
        rule(block_id: { string: simple(:s) }) { s.to_s }

        # Block width (grammar includes colon, e.g. ":2")
        rule(block_width: simple(:w)) { w.to_s.sub(/^:/, '').to_i }

        # Arrow direction
        rule(arrow_direction: { direction: simple(:d) }) { d.to_s }

        # Shape with label
        rule(
          block_shape: {
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
          block_shape: {
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

        # Process parsed diagram
        def self.apply(tree, diagram = nil)
          diagram ||= Diagram::BlockDiagram.new

          # Tree is an array of statement hashes
          statements = tree.is_a?(Array) ? tree : [tree]

          # Extract columns value first
          statements.each do |stmt|
            next unless stmt.is_a?(Hash)

            if stmt[:columns_keyword] && stmt[:columns_value]
              diagram.columns = stmt[:columns_value].to_s.to_i
              break
            end
          end

          # Process all statements
          process_statements(diagram, statements)

          diagram
        end

        def self.process_statements(diagram, statements, parent_block = nil)
          statements.each do |stmt|
            next unless stmt.is_a?(Hash)

            if stmt[:columns_keyword]
              # Already processed columns
              next
            elsif stmt[:space_keyword]
              # Space placeholder
              block = create_space_block
              if parent_block
                parent_block.add_child(block)
              else
                diagram.add_block(block)
              end
            elsif stmt[:arrow_id]
              # Arrow block
              block = create_arrow_block(stmt)
              if parent_block
                parent_block.add_child(block)
              else
                diagram.add_block(block)
              end
            elsif stmt[:compound_keyword]
              # Compound block
              block = create_compound_block(stmt)
              if stmt[:compound_statements]
                sub_stmts = stmt[:compound_statements]
                sub_stmts = [sub_stmts] unless sub_stmts.is_a?(Array)
                process_statements(diagram, sub_stmts, block)
              end
              if parent_block
                parent_block.add_child(block)
              else
                diagram.add_block(block)
              end
            elsif stmt[:block_id]
              # Regular block
              block = create_block(stmt)
              if parent_block
                parent_block.add_child(block)
              else
                diagram.add_block(block)
              end
            elsif stmt[:from] && stmt[:to]
              # Connection
              connection = create_connection(stmt)
              diagram.add_connection(connection)
            elsif stmt[:style_keyword]
              # Style directive
              style = create_style(stmt)
              diagram.add_style(style)
            end
          end
        end

        def self.create_space_block
          Diagram::Block.new.tap do |b|
            b.id = "space_#{rand(10000)}"
            b.block_type = 'space'
          end
        end

        def self.create_arrow_block(stmt)
          Diagram::Block.new.tap do |b|
            b.id = stmt[:arrow_id].to_s
            b.block_type = 'arrow'
            b.label = stmt[:arrow_label].to_s if stmt[:arrow_label]
            b.direction = stmt[:arrow_direction].to_s if stmt[:arrow_direction]
          end
        end

        def self.create_compound_block(stmt)
          Diagram::Block.new.tap do |b|
            # Generate ID if not provided
            b.id = stmt[:compound_id] ? stmt[:compound_id].to_s : "compound_#{rand(10000)}"
            b.is_compound = true
          end
        end

        def self.create_block(stmt)
          Diagram::Block.new.tap do |b|
            b.id = stmt[:block_id].to_s

            # Set width if specified
            if stmt[:block_width]
              width_val = stmt[:block_width]
              # Handle both transformed integers and raw strings like ":2"
              b.width = if width_val.is_a?(Hash)
                          width_val[:width].to_i
                        else
                          width_val.to_s.sub(/^:/, '').to_i
                        end
            end

            # Set shape and label if specified
            if stmt[:block_shape]
              shape_data = stmt[:block_shape]
              if shape_data.is_a?(Hash)
                # Check if it has open/close delimiters (raw parse tree)
                if shape_data[:open] && shape_data[:close]
                  delims = "#{shape_data[:open]}#{shape_data[:close]}"
                  b.shape = SHAPE_MAP[delims] || 'rect'
                  label = shape_data[:label].to_s
                  # Strip surrounding quotes if present
                  label = label.gsub(/^["']|["']$/, '')
                  b.label = label
                # Or if it's been transformed already
                elsif shape_data[:shape_type]
                  b.shape = shape_data[:shape_type] || 'rect'
                  label = shape_data[:label] || b.id
                  # Strip surrounding quotes if present
                  label = label.to_s.gsub(/^["']|["']$/, '')
                  b.label = label
                end
              end
            else
              b.label = b.id
            end
          end
        end

        def self.create_connection(stmt)
          Diagram::BlockConnection.new.tap do |c|
            c.from = stmt[:from].to_s
            c.to = stmt[:to].to_s

            arrow_type = if stmt[:arrow]
                          stmt[:arrow][:arrow_type] || stmt[:arrow][:line_type]
                        end

            if arrow_type
              c.connection_type = ARROW_MAP[arrow_type.to_s] || 'arrow'
            else
              c.connection_type = 'arrow'
            end
          end
        end

        def self.create_style(stmt)
          Diagram::BlockStyle.new.tap do |s|
            s.block_id = stmt[:style_target].to_s

            if stmt[:style_props]
              props = stmt[:style_props]
              props = [props] unless props.is_a?(Array)

              props.each do |prop|
                prop_str = prop.to_s.strip
                if prop_str.start_with?('fill:')
                  s.fill = prop_str.sub('fill:', '').strip
                elsif prop_str.start_with?('stroke:')
                  s.stroke = prop_str.sub('stroke:', '').strip
                elsif prop_str.start_with?('stroke-width:')
                  s.stroke_width = prop_str.sub('stroke-width:', '').strip
                else
                  s.properties << prop_str
                end
              end
            end
          end
        end
      end
    end
  end
end