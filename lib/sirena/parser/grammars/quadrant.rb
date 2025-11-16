# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for quadrant chart diagrams.
      #
      # Handles quadrant chart syntax including title, axis labels,
      # quadrant labels, and data points with coordinates and styling.
      #
      # @example Simple quadrant chart
      #   quadrantChart
      #     title Product Analysis
      #     x-axis Low Cost --> High Cost
      #     y-axis Low Value --> High Value
      #     quadrant-1 Invest
      #     Product A: [0.3, 0.7]
      #
      # @example With styling
      #   quadrantChart
      #     Product A: [0.3, 0.7] radius: 10, color: #ff0000
      class Quadrant < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # Header: quadrantChart
        rule(:header) do
          str('quadrantChart').as(:header) >> ws?
        end

        # Statements (title, axis labels, quadrant labels, points)
        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          title_declaration |
            x_axis_declaration |
            y_axis_declaration |
            quadrant_label_declaration |
            class_def_declaration |
            data_point |
            comment >> line_end
        end

        # Title declaration
        rule(:title_declaration) do
          str('title') >> space.repeat(1) >>
            title_text.as(:title) >>
            line_end
        end

        rule(:title_text) do
          (line_end.absent? >> any).repeat(1)
        end

        # X-axis: x-axis label1 --> label2
        rule(:x_axis_declaration) do
          str('x-axis') >> space.repeat(1) >>
            axis_label.as(:x_axis_left) >>
            space? >> str('-->') >> space? >>
            axis_label.as(:x_axis_right) >>
            line_end
        end

        # Y-axis: y-axis label1 --> label2
        rule(:y_axis_declaration) do
          str('y-axis') >> space.repeat(1) >>
            axis_label.as(:y_axis_bottom) >>
            space? >> str('-->') >> space? >>
            axis_label.as(:y_axis_top) >>
            line_end
        end

        # Axis label (can be quoted or unquoted)
        rule(:axis_label) do
          quoted_string | unquoted_axis_label
        end

        rule(:unquoted_axis_label) do
          (str('-->').absent? >> line_end.absent? >> any).repeat(1)
        end

        # Quadrant labels: quadrant-1 through quadrant-4
        rule(:quadrant_label_declaration) do
          str('quadrant-') >>
            match['1-4'].as(:quadrant_number) >>
            space.repeat(1) >>
            quadrant_label_text.as(:quadrant_label) >>
            line_end
        end

        rule(:quadrant_label_text) do
          (line_end.absent? >> any).repeat(1)
        end

        # Class definition: classDef name fill:#color
        rule(:class_def_declaration) do
          str('classDef') >> space.repeat(1) >>
            class_name.as(:class_name) >> space.repeat(1) >>
            (line_end.absent? >> any).repeat.as(:class_style) >>
            line_end
        end

        rule(:class_name) do
          match['a-zA-Z_'].repeat(1) >> match['a-zA-Z0-9_'].repeat
        end

        # Data point: label[:::class]: [x, y] [styling...]
        rule(:data_point) do
          point_label.as(:label) >>
            class_reference.maybe.as(:class_ref) >>
            space? >> colon >> space? >>
            coordinates.as(:coordinates) >>
            styling_params.maybe.as(:styling) >>
            line_end.as(:data_point)
        end

        # Point label (text before class reference or colon)
        rule(:point_label) do
          (str(':::').absent? >> colon.absent? >> any).repeat(1)
        end

        # Class reference: :::className
        rule(:class_reference) do
          str(':::') >> class_name
        end

        # Coordinates: [x, y]
        rule(:coordinates) do
          lbracket >>
            space? >>
            float.as(:x) >>
            space? >> comma >> space? >>
            float.as(:y) >>
            space? >>
            rbracket
        end

        # Optional styling parameters (flexible whitespace around commas)
        rule(:styling_params) do
          (space.repeat(1) >> styling_param >> (space? >> comma >> space? >> styling_param).repeat).maybe
        end

        rule(:styling_param) do
          radius_param |
            color_param |
            stroke_color_param |
            stroke_width_param
        end

        # radius: value
        rule(:radius_param) do
          str('radius') >> space? >> colon >> space? >>
            (float | integer).as(:radius)
        end

        # color: #hex
        rule(:color_param) do
          str('color') >> space? >> colon >> space? >>
            color_value.as(:color)
        end

        # stroke-color: #hex
        rule(:stroke_color_param) do
          str('stroke-color') >> space? >> colon >> space? >>
            color_value.as(:stroke_color)
        end

        # stroke-width: valuepx
        rule(:stroke_width_param) do
          str('stroke-width') >> space? >> colon >> space? >>
            (float | integer).as(:stroke_width) >>
            str('px').maybe
        end

        # Color value (#hex or named color)
        rule(:color_value) do
          str('#') >> match['0-9a-fA-F'].repeat(3, 8) |
            match['a-zA-Z'].repeat(1)
        end

        # Brackets
        rule(:lbracket) { str('[') }
        rule(:rbracket) { str(']') }
      end
    end
  end
end