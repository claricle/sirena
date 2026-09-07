# frozen_string_literal: true

module Sirena
  module Diagram
    # Cycle detection over a graph of box ids.
    #
    # Two callers, and their graphs run in OPPOSITE directions. The
    # parser transform passes what each subgraph's SOURCE encloses —
    # id to the ids inside it — before any model exists, so it can
    # refuse `a` inside `b` inside `a` the way mmdc does. The flowchart
    # model passes the `parent_id` graph — id to the id above it — of a
    # model somebody built by hand, where the same loop hangs those
    # boxes off each other and none of them is ever placed.
    #
    # So this reads edges, not parentage. It says whether following the
    # arrows returns you to where you started; what an arrow MEANS is
    # the caller's business, including which way round to read the pair
    # that comes back.
    #
    # @api private
    module Containment
      module_function

      # One walk over the whole graph, not one per box. Asking each box
      # in turn whether it reaches itself re-walks the same subtree once
      # per ancestor, which on the parser's graph — where a box lists
      # everything below it, not just its direct children — cost 2.6
      # seconds for 200 nested boxes against 0.2 for this.
      #
      # A box already walked to the end is left alone, which is what
      # makes it one pass — reaching it again cannot find a loop the
      # first visit missed.
      #
      # Keys are visited in insertion order, so a graph closing more
      # than one loop always reports the same one.
      #
      # @param graph [Hash{Object => Array}] id to the ids it points at
      # @return [Array(Object, Object), nil] the edge that closed the
      #   loop, as [from, to], or nil when there is none
      def looping_pair(graph)
        colour = {}
        graph.each_key do |root|
          found = back_edge(graph, root, colour)
          return found unless found.nil?
        end
        nil
      end

      # An explicit stack, not recursion. A flat chain of 4,000 boxes is
      # a source mmdc draws, and the recursive form raised a bare
      # SystemStackError out of the parse and into the caller.
      #
      # `colour` is threaded through the whole walk rather than reset
      # per root, which is what keeps it to one pass.
      #
      # Grey is on the path being walked, black is finished. Meeting a
      # grey box closes the loop, and BOTH ends get named rather than
      # just the one we arrived at: the parser turns the pair into
      # mermaid's "Setting b as parent of a", and naming one box twice
      # misreported every two-box loop.
      def back_edge(graph, root, colour)
        return nil if colour.key?(root)

        colour[root] = :grey
        stack = [[root, 0]]
        until stack.empty?
          box, taken = stack.last
          children = graph.fetch(box, [])
          if taken >= children.size
            colour[box] = :black
            stack.pop
            next
          end

          stack.last[1] = taken + 1
          child = children[taken]
          return [box, child] if colour[child] == :grey
          next if colour.key?(child)

          colour[child] = :grey
          stack << [child, 0]
        end
        nil
      end
      private_class_method :back_edge
    end
  end
end
