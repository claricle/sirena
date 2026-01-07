# frozen_string_literal: true

require "parslet"
require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Grammar for parsing Mermaid radar-beta chart syntax
      class Radar < Common

        rule(:diagram_type) { str("radar-beta") >> space? }

        rule(:title_line) do
          str("title") >> space >> (newline.absent? >> any).repeat(1).as(:title) >> eol
        end

        rule(:acc_title_line) do
          str("accTitle:") >> space >> (newline.absent? >> any).repeat(1).as(:acc_title) >> eol
        end

        rule(:acc_descr_line) do
          str("accDescr:") >> space >> (newline.absent? >> any).repeat(1).as(:acc_descr) >> eol
        end

        # Axis definition: axis A,B,C or axis A["Label"], B["Label"]
        rule(:axis_label) do
          str("[") >> str('"') >>
            match('[^"]').repeat(1).as(:label) >>
            str('"') >> str("]")
        end

        rule(:axis_item) do
          space? >>
            identifier.as(:id) >>
            axis_label.maybe >>
            space?
        end

        rule(:axis_line) do
          str("axis") >> space >>
            (axis_item >> (str(",") >> axis_item).repeat).as(:axes) >>
            eol
        end

        # Curve/dataset values
        # Supports: {1,2,3} or { A: 1, B: 2, C: 3 }
        rule(:value_number) { match["0-9"].repeat(1).as(:value) }

        rule(:positional_value) do
          space? >> value_number >> space?
        end

        rule(:named_value) do
          space? >>
            identifier.as(:axis) >>
            space? >> str(":") >> space? >>
            value_number >>
            space?
        end

        rule(:value_list) do
          positional_value >> (str(",") >> positional_value).repeat
        end

        rule(:named_value_list) do
          named_value >> (str(",") >> named_value).repeat
        end

        rule(:curve_values) do
          str("{") >>
            (named_value_list | value_list).as(:values) >>
            str("}")
        end

        rule(:curve_label) do
          str("[") >> str('"') >>
            match('[^"]').repeat(1).as(:label) >>
            str('"') >> str("]")
        end

        rule(:curve_line) do
          str("curve") >> space >>
            identifier.as(:id) >>
            curve_label.maybe >>
            curve_values >>
            eol
        end

        # Options
        rule(:ticks_line) do
          str("ticks") >> space >>
            match["0-9"].repeat(1).as(:ticks) >>
            eol
        end

        rule(:show_legend_line) do
          str("showLegend") >> space >>
            (str("true") | str("false")).as(:show_legend) >>
            eol
        end

        rule(:graticule_line) do
          str("graticule") >> space >>
            (str("polygon") | str("circular")).as(:graticule) >>
            eol
        end

        rule(:min_line) do
          str("min") >> space >>
            match["0-9"].repeat(1).as(:min) >>
            eol
        end

        rule(:max_line) do
          str("max") >> space >>
            match["0-9"].repeat(1).as(:max) >>
            eol
        end

        rule(:option_line) do
          ticks_line | show_legend_line | graticule_line |
            min_line | max_line
        end

        rule(:statement) do
          space? >> (
            title_line |
            acc_title_line |
            acc_descr_line |
            axis_line |
            curve_line |
            option_line |
            comment >> eol |
            space? >> newline
          )
        end

        rule(:body) { statement.repeat }

        rule(:radar_diagram) do
          diagram_type >> eol >>
            body.as(:statements)
        end

        root(:radar_diagram)
      end
    end
  end
end