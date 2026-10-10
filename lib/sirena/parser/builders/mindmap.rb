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
            # Handle icon and class declarations - apply to PREVIOUS node
            if node_data[:icon]
              icon = node_data[:icon].to_s
              if @all_nodes.last
                @all_nodes.last[:icon] = icon
              end
              return
            end

            if node_data[:classes]
              classes_str = node_data[:classes].to_s
              classes = classes_str.split(/\s+/)
              if @all_nodes.last
                @all_nodes.last[:classes] = classes
              end
              return
            end

            # Track minimum indentation for relative level calculation
            indent_size = get_indent_size(node_data[:indent])
            @min_indent = indent_size if @min_indent.nil? || indent_size < @min_indent

            # Calculate level from indentation (will be adjusted later)
            level = calculate_level(node_data[:indent])

            # Create the node
            content = extract_content(node_data)
            shape = extract_shape(node_data)

            node = {
              id: "node-#{@all_nodes.size}",
              content: content,
              level: level,
              shape: shape,
              icon: nil,
              classes: [],
              children: [],
              _indent_size: indent_size, # Store for later adjustment
            }

            @all_nodes << node

            # Build hierarchy
            if level.zero?
              @root = node
              @level_stack = [node]
            else
              # Find parent at previous level
              parent = find_parent(level)
              if parent
                parent[:children] << node
                node[:parent] = parent
              end

              # Update stack
              @level_stack = @level_stack[0..(level - 1)] + [node]
            end
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
          ROUND_COMMENT_LINE = /(?<=\n)#{ROUND_COMMENT_INDENT}*%%(?!\{)[^\r\n]+\r?\n?/o

          private

          def rebuild_hierarchy
            @root = nil
            # Stack of [indent_size, node] for the current ancestor chain:
            # each new node pops every entry whose indent is >= its own
            # (those are siblings or deeper nodes it isn't nested under),
            # then attaches under whatever remains on top.
            indent_stack = []

            @all_nodes.each do |node|
              indent_size = node.delete(:_indent_size) || 0

              # Clear old parent/children relationships
              node[:children] = []
              node.delete(:parent)

              indent_stack.pop while indent_stack.any? && indent_stack.last[0] >= indent_size

              if indent_stack.empty?
                # A second node with nothing above it in the stack is a
                # second root -- Mermaid rejects this ("Multiple roots are
                # illegal"). Without this guard it silently replaced @root
                # via ||= below and the first root's whole subtree, still
                # linked as node[:children] on the dropped node, vanished
                # from the diagram with no error.
                raise Sirena::Parser::ParseError, "Multiple roots are illegal" if @root

                node[:level] = 0
                @root = node
              else
                parent = indent_stack.last[1]
                node[:level] = parent[:level] + 1
                parent[:children] << node
                node[:parent] = parent
              end

              indent_stack << [indent_size, node]
            end
          end

          def get_indent_size(indent_data)
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            indent_str = if indent_data.is_a?(Array)
                           indent_data.join("")
                         else
                           indent_data.to_s
                         end

            indent_str.length
          end

          def calculate_level(indent_data)
            # Handle empty array or nil
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            # Convert to string and count length
            indent_str = if indent_data.is_a?(Array)
                           indent_data.join("")
                         else
                           indent_data.to_s
                         end

            return 0 if indent_str.empty?

            # Count spaces (2 or 4 spaces per level)
            spaces = indent_str.length
            # Try 2-space indentation first
            level = spaces / 2
            # If not evenly divisible, try 4-space
            level = spaces / 4 if spaces % 2 != 0

            level
          end

          def extract_content(node_data)
            return "" unless node_data[:content]

            content = node_data[:content].to_s
            if node_data[:shape_round]
              # Mermaid's comment strip is a textual pre-pass that runs
              # before quote lexing, so it removes a real comment LINE
              # (one already starting at a source line boundary) whether
              # or not that line sits inside quotes -- quoting a node's
              # content does not protect a line from it. What quoting
              # does change is the leading-newline normalisation below:
              # that is specific to an unquoted round shape's own
              # opening "(\n" convention and does not apply to a quoted
              # string's own leading newline.
              content = node_data[:round_quoted] ? strip_round_comments(content) : strip_round_extras(content)
            end
            content
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

            # Skip if no actual node data (just whitespace)
            next unless node_data[:content] || node_data[:icon] || node_data[:classes] ||
                       node_data[:shape_circle] || node_data[:shape_bang] ||
                       node_data[:shape_cloud] || node_data[:shape_hexagon] ||
                       node_data[:shape_square] || node_data[:shape_round]

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
