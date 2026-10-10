# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Builders
      # Transform for Mindmap diagrams
      class Mindmap < Parslet::Transform
        # Helper class to build mindmap tree from indented nodes
        class TreeBuilder
          # The first matching rule wins, in this order.
          SHAPE_NAMES = %w[circle bang cloud hexagon square round].freeze
          NODE_KEYS = %i[
            content icon classes shape_circle shape_bang shape_cloud
            shape_hexagon shape_square shape_round
          ].freeze

          attr_reader :root, :all_nodes

          def initialize
            @all_nodes = []
            @root = nil
            @level_stack = []
            @pending_icon = nil
            @pending_classes = []
            @min_indent = nil
          end

          def add_node(node_data)
            if node_data[:icon]
              return apply_to_previous(:icon, node_data[:icon].to_s)
            end
            return apply_classes(node_data[:classes]) if node_data[:classes]

            add_tree_node(node_data)
          end

          def node_data?(node_data)
            NODE_KEYS.any? { |key| node_data[key] }
          end

          def apply_to_previous(attribute, value)
            @all_nodes.last[attribute] = value if @all_nodes.last
          end

          def apply_classes(classes)
            apply_to_previous(:classes, classes.to_s.split(/\s+/))
          end

          def add_tree_node(node_data)
            indent_size = get_indent_size(node_data[:indent])
            if @min_indent.nil? || indent_size < @min_indent
              @min_indent = indent_size
            end
            level = calculate_level(node_data[:indent])
            node = node_entry(node_data, level, indent_size)
            @all_nodes << node
            link_node(node, level)
          end

          def node_entry(node_data, level, indent_size)
            {
              id: "node-#{@all_nodes.size}",
              content: extract_content(node_data), level: level,
              shape: extract_shape(node_data), icon: nil, classes: [],
              children: [], _indent_size: indent_size
            }
          end

          def link_node(node, level)
            if level.zero?
              @root = node
              @level_stack = [node]
            else
              attach_to_parent(node, find_parent(level))
              @level_stack = @level_stack[0..(level - 1)] + [node]
            end
          end

          def attach_to_parent(node, parent)
            return unless parent

            parent[:children] << node
            node[:parent] = parent
          end

          def finalize
            # Nothing to link if no real node was ever added.
            return if @min_indent.nil?

            # Rebuild hierarchy directly from each node's raw indentation,
            # not a level number banded to a fixed 2- or 4-space step. The
            # banded approach broke whenever one level's indent jumped by an
            # amount the fixed band didn't expect (e.g. a first indent step
            # of 4 columns from a zero-indent root): it produced a level
            # with no entry below it in the stack, so the child was computed
            # but never linked as anyone's child.
            rebuild_hierarchy
          end

          # A `%%` comment line embedded inside a multi-line round-shape
          # node's own content (e.g. "root(\n  one\n  %% hidden\n  two\n)").
          # Mermaid strips every such line, terminator included, before its
          # node lexer ever runs, but only when the `%%` starts a REAL
          # source line -- one already preceded by a newline -- and only
          # when at least one character follows it; `root(%% keep this)`
          # is one physical line (the `%%` sits after "root(", not at a
          # line start) so mermaid renders it literally, and a bare "%%"
          # with nothing after it is not a comment either. `^` matched at
          # the start of the extracted content string too, which isn't a
          # real line start unless something upstream already consumed a
          # newline to get there; `(?<=\n)` requires an actual newline
          # immediately before, without consuming it, so the string's own
          # start is never mistaken for one. Mirrors
          # Builders::Flowchart#strip_metadata_comments (flowchart.rb),
          # the same rule for a node's `@{...}` metadata block -- including
          # its indentation class: mermaid's own comment-strip regex uses
          # JavaScript's `\s`, wider than ASCII space/tab (e.g. it matches a
          # no-break space), so `[ \t]` alone left a comment unrecognised
          # when it was indented with one.
          ROUND_COMMENT_INDENT = '[\t\n\v\f\r \u00a0\u1680\u2000-\u200a' \
                                 '\u2028\u2029\u202f\u205f\u3000\ufeff]'
          ROUND_COMMENT_LINE = Regexp.new(
            "(?<=\\n)#{ROUND_COMMENT_INDENT}*%%(?!\\{)" \
            "[^\\r\\n]+\\r?\\n?",
          )

          private

          def rebuild_hierarchy
            @root = nil
            # Stack of [indent_size, node] for the current ancestor chain:
            # each new node pops every entry whose indent is >= its own
            # (those are siblings or deeper nodes it isn't nested under),
            # then attaches under whatever remains on top.
            indent_stack = []
            @all_nodes.each { |node| rebuild_node(node, indent_stack) }
          end

          def rebuild_node(node, indent_stack)
            indent_size = prepare_for_rebuild(node)
            discard_siblings(indent_stack, indent_size)
            attach_rebuilt_node(node, indent_stack)
            indent_stack << [indent_size, node]
          end

          def prepare_for_rebuild(node)
            indent_size = node.delete(:_indent_size) || 0
            node[:children] = []
            node.delete(:parent)
            indent_size
          end

          def discard_siblings(indent_stack, indent_size)
            while indent_stack.any? && indent_stack.last[0] >= indent_size
              indent_stack.pop
            end
          end

          def attach_rebuilt_node(node, indent_stack)
            return install_root(node) if indent_stack.empty?

            parent = indent_stack.last[1]
            node[:level] = parent[:level] + 1
            attach_to_parent(node, parent)
          end

          # A second node with no ancestor is a second root. Mermaid rejects
          # it rather than silently discarding the first root and its subtree.
          def install_root(node)
            if @root
              raise Sirena::Parser::ParseError, "Multiple roots are illegal"
            end

            node[:level] = 0
            @root = node
          end

          def get_indent_size(indent_data)
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            indent_string(indent_data).length
          end

          def calculate_level(indent_data)
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            indent_str = indent_string(indent_data)
            return 0 if indent_str.empty?

            spaces = indent_str.length
            spaces.even? ? spaces / 2 : spaces / 4
          end

          def indent_string(indent_data)
            separator = ""
            return indent_data.join(separator) if indent_data.is_a?(Array)

            indent_data.to_s
          end

          def extract_content(node_data)
            return "" unless node_data[:content]

            content = node_data[:content].to_s
            return content unless node_data[:shape_round]

            round_content(content, node_data[:round_quoted])
          end

          # Quoting protects the leading newline but not a real comment line:
          # Mermaid strips those comments before quote lexing.
          def round_content(content, quoted)
            quoted ? strip_round_comments(content) : strip_round_extras(content)
          end

          def strip_round_comments(content)
            content.gsub(ROUND_COMMENT_LINE, "")
          end

          def strip_round_extras(content)
            # Drop embedded comment-only lines first (matching mermaid's own
            # pre-lexer pass), then the one leading newline that a
            # multi-line node's own opening "(\n" legitimately introduces --
            # mermaid's rendered output drops exactly that line break and
            # nothing else. `\r?` handles a caller that passes CRLF source
            # straight to this parser without going through
            # `Source.normalize` (Engine's real render path always does).
            strip_round_comments(content).sub(/\A\r?\n/, "")
          end

          def extract_shape(node_data)
            SHAPE_NAMES.find { |name| node_data[:"shape_#{name}"] } ||
              "default"
          end

          def find_parent(level)
            # Parent is the last node at level - 1; level 0 is the root and
            # never asks.
            @level_stack[level - 1]
          end
        end

        # Transform the nodes array into a tree structure
        rule(nodes: subtree(:nodes)) do
          builder = TreeBuilder.new
          nodes_array = Array(nodes)

          nodes_array.each do |node_data|
            next unless node_data.is_a?(Hash)

            next unless builder.node_data?(node_data)

            builder.add_node(node_data)
          end

          # Finalize to adjust levels and rebuild hierarchy
          builder.finalize

          {
            root: builder.root,
            nodes: builder.all_nodes,
          }
        end
      end
    end
  end
end
