# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Builders
      # Transform for Radar diagrams
      class Radar < Parslet::Transform
        RESULT_HANDLERS = {
          title: :apply_scalar,
          acc_title: :apply_scalar,
          acc_descr: :apply_scalar,
          axes: :apply_axes,
          curve: :apply_curve,
          option: :apply_option,
        }.freeze
        private_constant :RESULT_HANDLERS

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
            values: vals,
          }
        end

        rule(id: simple(:id), values: subtree(:vals)) do
          {
            type: :curve,
            id: id.to_s,
            label: id.to_s,
            values: vals,
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
          # A single-axis statement yields a Hash, and Kernel#Array turns a
          # Hash into its key/value pairs — so `axis A` became
          # [[:id, "A"], [:label, "A"]]. Assignment used to hide that,
          # because a later statement overwrote it; accumulating keeps it and
          # the renderer then fails on a Symbol index.
          {
            type: :axes,
            axes: axes.is_a?(Array) ? axes : [axes],
          }
        end

        # Transform options
        rule(ticks: simple(:ticks)) do
          { type: :option, key: :ticks, value: ticks.to_s.to_i }
        end

        rule(show_legend: simple(:show_legend)) do
          {
            type: :option,
            key: :show_legend,
            value: show_legend.to_s == "true",
          }
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
          Radar.build(statements)
        end

        def self.build(statements)
          result = empty_result
          Array(statements).grep(Hash).each do |statement|
            apply_statement(result, statement)
          end
          result
        end

        def self.empty_result
          {
            title: nil,
            acc_title: nil,
            acc_descr: nil,
            axes: [],
            curves: [],
            options: {},
          }
        end

        def self.apply_statement(result, statement)
          handler = RESULT_HANDLERS[statement[:type]]
          send(handler, result, statement) if handler
        end

        def self.apply_scalar(result, statement)
          result[statement[:type]] = statement[statement[:type]]
        end

        def self.apply_axes(result, statement)
          result[:axes].concat(statement[:axes])
        end

        def self.apply_curve(result, statement)
          result[:curves] << statement
        end

        def self.apply_option(result, statement)
          result[:options][statement[:key]] = statement[:value]
        end
      end
    end
  end
end
