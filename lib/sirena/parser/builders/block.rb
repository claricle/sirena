# frozen_string_literal: true

require "parslet"
require_relative "../../diagram/block"

module Sirena
  module Parser
    module Builders
      # Transform for converting block diagram parse trees to diagram models.
      #
      # Handles transformation of blocks, compound blocks, connections, and
      # styling directives from Parslet parse trees into Block objects.
      class Block < Parslet::Transform
        # Shape delimiter to type mapping
        SHAPE_MAP = {
          "[]" => "rect",
          "(())" => "circle",
        }.freeze

        # Arrow type mapping
        ARROW_MAP = {
          "-->" => "arrow",
          "---" => "line",
        }.freeze

        STATEMENT_HANDLERS = [
          [:columns_keyword, nil],
          %i[space_keyword process_space],
          %i[arrow_id process_arrow],
          %i[compound_keyword process_compound],
          %i[block_id process_block],
          [%i[from to], :process_connection],
          %i[style_keyword process_style],
        ].freeze

        # Block ID
        rule(block_id: simple(:id)) { id.to_s }
        rule(block_id: { string: simple(:s) }) { s.to_s }

        # Block width (grammar includes colon, e.g. ":2")
        rule(block_width: simple(:w)) { w.to_s.sub(/^:/, "").to_i }

        # Arrow direction
        rule(arrow_direction: { direction: simple(:d) }) { d.to_s }

        # Shape with label
        rule(
          block_shape: {
            open: simple(:o),
            label: simple(:l),
            close: simple(:c),
          },
        ) do
          delims = "#{o}#{c}"
          {
            shape_type: SHAPE_MAP[delims] || "rect",
            label: l.to_s.strip,
          }
        end

        # Handle empty labels
        rule(
          block_shape: {
            open: simple(:o),
            label: sequence(:_),
            close: simple(:c),
          },
        ) do
          delims = "#{o}#{c}"
          {
            shape_type: SHAPE_MAP[delims] || "rect",
            label: "",
          }
        end

        # Process parsed diagram.
        #
        # Deliberately builds its own diagram rather than accepting one. Ids
        # are positional, so feeding a second tree into a populated diagram
        # would re-issue "compound-1" and the later block would overwrite the
        # earlier one. No caller ever passed a diagram, so the parameter only
        # exposed that hazard.
        def apply(tree)
          diagram = Diagram::Block.new
          statements = tree.is_a?(Array) ? tree : [tree]
          assign_columns(diagram, statements)
          process_statements(diagram, statements)
          diagram
        end

        def assign_columns(diagram, statements)
          statement = statements.find do |item|
            item.is_a?(Hash) && item[:columns_keyword] && item[:columns_value]
          end
          diagram.columns = statement[:columns_value].to_s.to_i if statement
        end

        def process_statements(diagram, statements, parent_block = nil)
          statements.each_with_index do |stmt, index|
            next unless stmt.is_a?(Hash)

            handler = statement_handler(stmt)
            send(handler, diagram, stmt, parent_block, index) if handler
          end
        end

        def statement_handler(stmt)
          match = STATEMENT_HANDLERS.find do |keys, _|
            Array(keys).all? { |key| stmt[key] }
          end
          match&.last
        end

        def process_space(diagram, _stmt, parent_block, index)
          block = create_space_block(parent_block, index)
          add_block(diagram, parent_block, block)
        end

        def process_arrow(diagram, stmt, parent_block, _index)
          add_block(diagram, parent_block, create_arrow_block(stmt))
        end

        def process_compound(diagram, stmt, parent_block, index)
          block = create_compound_block(stmt, parent_block, index)
          process_compound_children(diagram, stmt[:compound_statements], block)
          add_block(diagram, parent_block, block)
        end

        def process_compound_children(diagram, statements, block)
          return unless statements

          children = statements.is_a?(Array) ? statements : [statements]
          process_statements(diagram, children, block)
        end

        def process_block(diagram, stmt, parent_block, _index)
          add_block(diagram, parent_block, create_block(stmt))
        end

        def process_connection(diagram, stmt, _parent_block, _index)
          diagram.add_connection(create_connection(stmt))
        end

        def process_style(diagram, stmt, _parent_block, _index)
          diagram.add_style(create_style(stmt))
        end

        def add_block(diagram, parent_block, block)
          return parent_block.add_child(block) if parent_block

          diagram.add_block(block)
        end

        # Anonymous ids are derived from the statement's position and its
        # parent, never randomly. A random id varies in digit length, and
        # that length reaches TextMeasurement, so the same source used to
        # render at different sizes between runs.
        #
        # The hyphen separator is what keeps these ids out of the author's
        # namespace: identifier_char is [a-zA-Z0-9_], so no bare block id can
        # ever spell "compound-1". An underscore could, and the collision
        # silently dropped the generated block's children from the SVG.
        def anonymous_id(kind, parent_block, index)
          prefix = parent_block ? "#{parent_block.id}-" : ""
          "#{prefix}#{kind}-#{index}"
        end

        def create_space_block(parent_block, index)
          Diagram::BlockNode.new.tap do |b|
            b.id = anonymous_id("space", parent_block, index)
            b.block_type = "space"
          end
        end

        def create_arrow_block(stmt)
          Diagram::BlockNode.new.tap do |b|
            b.id = stmt[:arrow_id].to_s
            b.block_type = "arrow"
            b.label = stmt[:arrow_label].to_s if stmt[:arrow_label]
            b.direction = stmt[:arrow_direction].to_s if stmt[:arrow_direction]
          end
        end

        def create_compound_block(stmt, parent_block, index)
          Diagram::BlockNode.new.tap do |b|
            b.id = if stmt[:compound_id]
                     stmt[:compound_id].to_s
                   else
                     anonymous_id("compound", parent_block, index)
                   end
            b.is_compound = true
          end
        end

        def create_block(stmt)
          Diagram::BlockNode.new.tap do |b|
            b.id = stmt[:block_id].to_s
            assign_width(b, stmt[:block_width])
            assign_shape(b, stmt[:block_shape])
          end
        end

        def assign_width(block, width)
          return unless width

          value = width.is_a?(Hash) ? width[:width] : width.to_s.sub(/^:/, "")
          block.width = value.to_i
        end

        def assign_shape(block, shape)
          return block.label = block.id unless shape
          return unless shape.is_a?(Hash)

          handler = shape_handler(shape)
          send(handler, block, shape) if handler
        end

        def shape_handler(shape)
          return :assign_raw_shape if shape[:open] && shape[:close]

          :assign_transformed_shape if shape[:shape_type]
        end

        def assign_transformed_shape(block, shape)
          block.shape = shape[:shape_type] || "rect"
          block.label = unquote(shape[:label] || block.id)
        end

        def assign_raw_shape(block, shape)
          delimiters = "#{shape[:open]}#{shape[:close]}"
          block.shape = SHAPE_MAP[delimiters] || "rect"
          block.label = unquote(shape[:label])
        end

        def unquote(label)
          label.to_s.gsub(/^["']|["']$/, "")
        end

        def create_connection(stmt)
          Diagram::BlockConnection.new.tap do |c|
            c.from = stmt[:from].to_s
            c.to = stmt[:to].to_s
            c.connection_type = connection_type(stmt[:arrow])
          end
        end

        def connection_type(arrow)
          return "arrow" unless arrow

          type = arrow[:arrow_type] || arrow[:line_type]
          ARROW_MAP[type.to_s] || "arrow"
        end

        def create_style(stmt)
          Diagram::BlockStyle.new.tap do |s|
            s.block_id = stmt[:style_target].to_s
            assign_style_properties(s, stmt[:style_props])
          end
        end

        def assign_style_properties(style, properties)
          return unless properties

          values = properties.is_a?(Array) ? properties : [properties]
          values.each { |property| assign_style_property(style, property) }
        end

        def assign_style_property(style, property)
          value = property.to_s.strip
          if value.start_with?("fill:")
            style.fill = property_value(value, "fill:")
          elsif value.start_with?("stroke:")
            style.stroke = property_value(value, "stroke:")
          elsif value.start_with?("stroke-width:")
            style.stroke_width = property_value(value, "stroke-width:")
          else
            style.properties << value
          end
        end

        def property_value(property, prefix)
          property.sub(prefix, "").strip
        end
      end
    end
  end
end
