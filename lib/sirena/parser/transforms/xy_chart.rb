# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for XY Chart diagrams
      class XYChart < Parslet::Transform
        # Transform title (from grammar: {:title=>{:string=>"..."}} )
        rule(title: { string: simple(:title) }) do
          { type: :title, title: title.to_s }
        end
        
        # Transform values - keep as-is for now, will determine numeric vs categorical later
        rule(value: simple(:v)) do
          # Try to convert to number if it looks numeric, otherwise keep as string
          str = v.to_s
          if str.match?(/^\d+(\.\d+)?$/)
            str.to_f
          else
            str
          end
        end

        # Transform X-axis with label
        rule(x_label: { string: simple(:label) }, x_values: subtree(:values)) do
          {
            type: :x_axis,
            label: label.to_s,
            values: Array(values)
          }
        end

        rule(x_values: subtree(:values)) do
          {
            type: :x_axis,
            label: nil,
            values: Array(values)
          }
        end

        # Transform Y-axis with label
        rule(y_label: { string: simple(:label) }, y_min: simple(:min), y_max: simple(:max)) do
          {
            type: :y_axis,
            label: label.to_s,
            min: min.to_s.to_f,
            max: max.to_s.to_f
          }
        end

        rule(y_min: simple(:min), y_max: simple(:max)) do
          {
            type: :y_axis,
            label: nil,
            min: min.to_s.to_f,
            max: max.to_s.to_f
          }
        end

        # Transform line dataset
        rule(line_values: subtree(:values)) do
          {
            type: :dataset,
            chart_type: :line,
            label: "Line",
            values: Array(values)
          }
        end

        # Transform bar dataset
        rule(bar_values: subtree(:values)) do
          {
            type: :dataset,
            chart_type: :bar,
            label: "Bar",
            values: Array(values)
          }
        end

        # Transform named dataset
        rule(dataset_label: { string: simple(:label) }, dataset_values: subtree(:values)) do
          {
            type: :dataset,
            chart_type: :line,
            label: label.to_s,
            values: Array(values)
          }
        end

        # Transform the entire diagram
        rule(statements: subtree(:statements)) do
          result = {
            title: nil,
            x_axis: nil,
            y_axis: nil,
            datasets: []
          }

          Array(statements).each do |stmt|
            next unless stmt.is_a?(Hash)

            case stmt[:type]
            when :title
              result[:title] = stmt[:title]
            when :x_axis
              result[:x_axis] = {
                label: stmt[:label],
                values: stmt[:values]
              }
            when :y_axis
              result[:y_axis] = {
                label: stmt[:label],
                min: stmt[:min],
                max: stmt[:max]
              }
            when :dataset
              result[:datasets] << {
                chart_type: stmt[:chart_type],
                label: stmt[:label],
                values: stmt[:values]
              }
            end
          end

          result
        end
      end
    end
  end
end