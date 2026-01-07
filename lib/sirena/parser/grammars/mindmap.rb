# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Mindmap diagrams
      class Mindmap < Common
        rule(:diagram) do
          space? >>
            header >>
            (node_line).repeat(0).as(:nodes) >>
            space?
        end

        rule(:header) do
          str("mindmap") >> (newline | eof)
        end

        rule(:node_line) do
          empty_line | node_with_content
        end

        rule(:empty_line) do
          space? >> newline
        end

        rule(:node_with_content) do
          str(' ').repeat.as(:indent) >>
            node >>
            (newline | eof)
        end

        rule(:node) do
          node_with_icon |
          node_with_class |
          node_with_shape |
          node_plain
        end

        # Node with icon: ::icon(fa fa-book)
        rule(:node_with_icon) do
          str("::icon(") >>
            match('[^)]').repeat(1).as(:icon) >>
            str(")")
        end

        # Node with class: :::className
        rule(:node_with_class) do
          str(":::") >>
            match('[^\r\n]').repeat(1).as(:classes)
        end

        # Node with shape (optional identifier prefix)
        rule(:node_with_shape) do
          match['a-zA-Z0-9_'].repeat >>
            (circle_shape | bang_shape | cloud_shape | hexagon_shape | square_shape)
        end

        # ((text)) - circle
        rule(:circle_shape) do
          str("((") >>
            match('[^)]').repeat(1).as(:content) >>
            str("))") >>
            str("").as(:shape_circle)
        end

        # ))text(( - bang
        rule(:bang_shape) do
          str("))") >>
            match('[^(]').repeat(1).as(:content) >>
            str("((") >>
            str("").as(:shape_bang)
        end

        # )text( - cloud
        rule(:cloud_shape) do
          str(")") >>
            match('[^(]').repeat(1).as(:content) >>
            str("(") >>
            str("").as(:shape_cloud)
        end

        # {{text}} - hexagon
        rule(:hexagon_shape) do
          str("{{") >>
            match('[^}]').repeat(1).as(:content) >>
            str("}}") >>
            str("").as(:shape_hexagon)
        end

        # [text] - square (handles quoted content like ["text with []"])
        rule(:square_shape) do
          str("[") >>
            (
              # Quoted content: ["text..."]
              (str('"') >> match('[^"]').repeat(1).as(:content) >> str('"')) |
              # Regular content without quotes
              match('[^\]]').repeat(1).as(:content)
            ) >>
            str("]") >>
            str("").as(:shape_square)
        end

        # Plain text node
        rule(:node_plain) do
          match('[^\r\n:]').repeat(1).as(:content)
        end

        root(:diagram)
      end
    end
  end
end