# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for Radar diagrams
      class Radar < Parslet::Transform
        # Transform axis definition
        rule(id: simple(:id), label: simple(:label)) do
          { id: id.to_s, label: label.to_s }
        end

        rule(id: simple(:id)) do
          { id: id.to_s, label: id.to_s }
        end

        # Transform positional values (simple list)
        rule(value: simple(:v)) do
          v.to_s.to_f
        end

        # Transform named values (axis: value pairs)
        rule(axis: simple(:axis), value: simple(:v)) do
          { axis: axis.to_s, value: v.to_s.to_f }
        end

        # Transform curve definition
        rule(id: simple(:id), label: simple(:label), values: subtree(:vals)) do
          {
            type: :curve,
            id: id.to_s,
            label: label.to_s,
            values: vals
          }
        end

        rule(id: simple(:id), values: subtree(:vals)) do
          {
            type: :curve,
            id: id.to_s,
            label: id.to_s,
            values: vals
          }
        end

        # Transform title
        rule(title: simple(:title)) do
          { type: :title, title: title.to_s }
        end

        # Transform accessibility
        rule(acc_title: simple(:acc_title)) do
          { type: :acc_title, acc_title: acc_title.to_s }
        end

        rule(acc_descr: simple(:acc_descr)) do
          { type: :acc_descr, acc_descr: acc_descr.to_s }
        end

        # Transform axes definition
        rule(axes: subtree(:axes)) do
          {
            type: :axes,
            axes: Array(axes)
          }
        end

        # Transform options
        rule(ticks: simple(:ticks)) do
          { type: :option, key: :ticks, value: ticks.to_s.to_i }
        end

        rule(show_legend: simple(:show_legend)) do
          { type: :option, key: :show_legend, value: show_legend.to_s == "true" }
        end

        rule(graticule: simple(:graticule)) do
          { type: :option, key: :graticule, value: graticule.to_s }
        end

        rule(min: simple(:min)) do
          { type: :option, key: :min, value: min.to_s.to_f }
        end

        rule(max: simple(:max)) do
          { type: :option, key: :max, value: max.to_s.to_f }
        end

        # Transform the entire diagram
        rule(statements: subtree(:statements)) do
          result = {
            title: nil,
            acc_title: nil,
            acc_descr: nil,
            axes: [],
            curves: [],
            options: {}
          }

          Array(statements).each do |stmt|
            next unless stmt.is_a?(Hash)

            case stmt[:type]
            when :title
              result[:title] = stmt[:title]
            when :acc_title
              result[:acc_title] = stmt[:acc_title]
            when :acc_descr
              result[:acc_descr] = stmt[:acc_descr]
            when :axes
              result[:axes] = stmt[:axes]
            when :curve
              result[:curves] << stmt
            when :option
              result[:options][stmt[:key]] = stmt[:value]
            end
          end

          result
        end
      end
    end
  end
end