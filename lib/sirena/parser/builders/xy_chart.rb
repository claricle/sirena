# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Builders
      # Transform for XY Chart diagrams
      class XyChart < Parslet::Transform
        # Transform title (from grammar: {:title=>{:string=>"..."}} )
        rule(title: { string: simple(:title) }) do
          { type: :title, title: title.to_s }
        end

        # Transform values - keep as-is for now, will determine numeric vs
        # categorical later
        rule(value: simple(:v)) do
          # Try to convert to number if it looks numeric, otherwise keep as
          # string
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
            values: Array(values),
          }
        end

        rule(x_values: subtree(:values)) do
          {
            type: :x_axis,
            label: nil,
            values: Array(values),
          }
        end

        # Transform Y-axis with label
        rule(
          y_label: { string: simple(:label) },
          y_min: simple(:min),
          y_max: simple(:max),
        ) do
          {
            type: :y_axis,
            label: label.to_s,
            min: min.to_s.to_f,
            max: max.to_s.to_f,
          }
        end

        rule(y_min: simple(:min), y_max: simple(:max)) do
          {
            type: :y_axis,
            label: nil,
            min: min.to_s.to_f,
            max: max.to_s.to_f,
          }
        end

        # Transform line dataset
        rule(line_values: subtree(:values)) do
          {
            type: :dataset,
            chart_type: :line,
            label: "Line",
            values: Array(values),
          }
        end

        # Transform bar dataset
        rule(bar_values: subtree(:values)) do
          {
            type: :dataset,
            chart_type: :bar,
            label: "Bar",
            values: Array(values),
          }
        end

        # Transform named dataset
        rule(
          dataset_label: { string: simple(:label) },
          dataset_values: subtree(:values),
        ) do
          {
            type: :dataset,
            chart_type: :line,
            label: label.to_s,
            values: Array(values),
          }
        end

        # Transform the entire diagram
        rule(statements: subtree(:statements)) do
          XyChart.build(statements)
        end

        def self.build(statements)
          result = {
            title: nil,
            x_axis: nil,
            y_axis: nil,
            datasets: [],
          }
          Array(statements).grep(Hash).each do |statement|
            apply_statement(result, statement)
          end
          result
        end

        def self.apply_statement(result, statement)
          case statement[:type]
          when :title
            result[:title] = statement[:title]
          when :x_axis
            result[:x_axis] = axis_values(statement, :values)
          when :y_axis
            result[:y_axis] = axis_values(statement, :min, :max)
          when :dataset
            result[:datasets] << dataset(statement)
          end
        end

        def self.axis_values(statement, *keys)
          keys.each_with_object(label: statement[:label]) do |key, values|
            values[key] = statement[key]
          end
        end

        def self.dataset(statement)
          {
            chart_type: statement[:chart_type],
            label: statement[:label],
            values: statement[:values],
          }
        end
      end
    end
  end
end
