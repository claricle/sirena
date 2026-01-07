# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for info diagrams.
      #
      # Handles simple info diagram syntax with optional showInfo flag.
      #
      # @example Simple info diagram
      #   info
      #
      # @example Info diagram with showInfo flag
      #   info showInfo
      class Info < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            body.maybe >>
            ws?
        end

        # Header: info [showInfo] [additional text...]
        rule(:header) do
          str('info').as(:header) >>
            (space.repeat(1) >> show_info_inline).maybe.as(:show_info_inline) >>
            (space.repeat(1) >> additional_text).maybe >>
            ws?
        end

        # showInfo on same line as info
        rule(:show_info_inline) do
          str('showInfo').as(:show_info)
        end

        # Additional text after info keyword (ignored, but not showInfo)
        rule(:additional_text) do
          (str('showInfo').absent? >> line_end.absent? >> any).repeat(1)
        end

        # Body: showInfo on separate line
        rule(:body) do
          (space.repeat >> show_info_statement >> line_end).repeat(1).as(:show_info_body)
        end

        rule(:show_info_statement) do
          str('showInfo')
        end
      end
    end
  end
end