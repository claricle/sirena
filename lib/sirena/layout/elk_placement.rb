# frozen_string_literal: true

require "elkrb"
require_relative "base"
require_relative "elk_notices"

module Sirena
  module Layout
    # Positions an ELK-shaped graph Hash with elkrb's layered algorithm.
    #
    # Same contract as Grid.apply: x/y/width/height are written into the
    # Hash in place, a child positioned inside its parent. An elkrb
    # failure raises LayoutError; nothing falls back to Grid.
    #
    # elkrb 2 lays out all four directions itself and reads direction and
    # spacing from the graph's layoutOptions.
    class ElkPlacement
      ElkNotices.install

      DOWN = "DOWN"
      LEFT = "LEFT"
      RIGHT = "RIGHT"
      UP = "UP"
      DIRECTIONS = [DOWN, LEFT, RIGHT, UP].freeze
      # The side of a layer where its first layer starts: nodes of unequal
      # size line up on it instead of being centred across the layer.
      # With the sweeps off elkrb keeps the model order of a layer apart
      # from its greedy switch; a caller that wants dagre-like ordering
      # sets elk.layered.crossingMinimization.strategy itself.
      NO_SWEEP = "NONE"
      # Boxes the caller lists first stay first in their layer.
      MODEL_ORDER = {
        Base::ElkOptions::MODEL_ORDER => "NODES_AND_EDGES",
      }.freeze
      SPACINGS = [Base::ElkOptions::NODE_NODE_SPACING,
                  Base::ElkOptions::LAYER_SPACING].freeze
      # elkrb statuses of options that parse but never change its result.
      NOT_ACTED_ON = %i[accepted unsupported].freeze
      LAYER_START = {
        DOWN => "TOP", UP => "BOTTOM", RIGHT => "LEFT", LEFT => "RIGHT"
      }.freeze

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      # @raise [LayoutError] if elkrb cannot lay the graph out
      def self.apply(graph)
        new.apply(graph)
      end

      def apply(graph)
        options = graph[:layoutOptions] || {}
        place(graph, options)
        graph
      rescue Elkrb::Error => e
        raise LayoutError, "elkrb layout failed: #{e.message}"
      end

      private

      def place(graph, options)
        direction = direction_of(options)
        unless DIRECTIONS.include?(direction)
          raise LayoutError,
                "elkrb layered cannot lay out direction #{direction}"
        end

        placed = Elkrb.layout(layout_input(graph, options))
        copy_layout(graph, placed)
      end

      # elkrb 2 reads direction and spacing from the graph's own
      # layoutOptions, and defaults to RIGHT, so both are set explicitly.
      def layered_options(options)
        {
          Base::ElkOptions::DIRECTION => DOWN,
          "elk.alignment" => LAYER_START.fetch(direction_of(options)),
          "elk.separateConnectedComponents" => false,
          Base::ElkOptions::CROSSING_MINIMIZATION =>
            options.fetch(Base::ElkOptions::CROSSING_MINIMIZATION, NO_SWEEP),
        }.merge(options.slice(Base::ElkOptions::DIRECTION, *SPACINGS)).compact
      end

      # Sirena's graphs carry options for other layout engines too. elkrb
      # parses the ones it does not act on and warns about each on every
      # layout, so only the options that change its result are handed over.
      def acted_on(options)
        options.reject do |id, _value|
          NOT_ACTED_ON.include?(Elkrb.known_layout_options.dig(id, :status))
        end
      end

      def direction_of(options)
        options.fetch(Base::ElkOptions::DIRECTION, DOWN)
      end

      def layout_input(graph, options)
        input = graph.dup
        own = graph[:layoutOptions] || {}
        input[:layoutOptions] = acted_on(
          MODEL_ORDER.merge(own).merge(layered_options(options)),
        )
        copy_input_children(input, graph, options)
        copy_input_edges(input, graph)
        input
      end

      def copy_input_children(input, graph, options)
        return unless graph[:children]

        input[:children] = graph[:children].map do |child|
          layout_input(child, options)
        end
      end

      def copy_input_edges(input, graph)
        return unless graph[:edges]

        links = Hash.new { |hash, node| hash[node] = [] }
        input[:edges] = graph[:edges].reject do |edge|
          closes_cycle?(edge, links)
        end
      end

      def closes_cycle?(edge, links)
        source = edge[:sources]&.first
        target = edge[:targets]&.first
        return false unless source && target
        return true if cycle_between?(source, target, links)

        links[source] << target
        false
      end

      def cycle_between?(source, target, links)
        source == target || reachable?(target, source, links)
      end

      # elkrb 1.0.2 only breaks root-level cycles. Keep its private input
      # acyclic so nested cycles cannot recurse indefinitely during placement.
      def reachable?(start, target, links)
        pending = [start]
        visited = {}
        until pending.empty?
          node = pending.pop
          return true if node == target
          next if visited[node]

          visited[node] = true
          pending.concat(links[node])
        end
        false
      end

      def copy_layout(graph, placed)
        copy_positions(graph[:children] || [], placed.children || [])
        copy_sections(graph[:edges] || [], placed.edges || [])
      end

      # elkrb keeps child order, so the two trees are walked in step.
      def copy_positions(children, placed)
        children.zip(placed).each do |child, result|
          child.merge!(x: result.x, y: result.y,
                       width: result.width, height: result.height)
          copy_layout(child, result)
        end
      end

      def copy_sections(edges, placed)
        placed_by_id = placed.group_by(&:id)
        edges.each do |edge|
          copy_edge_sections(edge, placed_by_id[edge[:id]]&.shift)
        end
      end

      def copy_edge_sections(edge, result)
        return unless result

        sections = result.sections
        return if sections.nil? || sections.empty?

        edge[:sections] = sections.map { |section| section_hash(section) }
      end

      def section_hash(section)
        {
          startPoint: point_hash(section.start_point),
          endPoint: point_hash(section.end_point),
          bendPoints: (section.bend_points || []).map { |p| point_hash(p) },
        }
      end

      def point_hash(point)
        { x: point.x, y: point.y }
      end
    end
  end
end
