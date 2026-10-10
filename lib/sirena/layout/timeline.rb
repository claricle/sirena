# frozen_string_literal: true

require_relative "base"
require_relative "timeline_flow"
require_relative "../diagram/timeline"
require_relative "../notation/mermaid/ir_adapters/timeline"

module Sirena
  module Layout
    # Builds final timeline geometry for the SVG renderer, placing cards
    # where mmdc places them.
    class Timeline < Base
      # mmdc's left margin: the base arrow starts here.
      AXIS_X = 150
      # Space around the drawing in the viewBox.
      FRAME = 50
      TITLE_Y = 20
      TITLE_ASCENT = 31
      TITLE_SIZE = 33
      EMPTY_AXIS_WIDTH = 300

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :acc_title, :string
        attribute :acc_description, :string
        attribute :title, :string
        attribute :title_x, :float
        attribute :title_y, :float
        attribute :title_size, :float
        attribute :cards, TimelineCard, collection: true,
                                        default: -> { [] }
        attribute :axis, TimelineLine
      end

      private

      def scene(diagram)
        document = ir_document(diagram)
        sectioned = sectioned?(document)
        flow = TimelineFlow.new(groups(document), sectioned: sectioned)
        shift_to_origin(build_scene(document, flow))
      end

      def build_scene(document, flow)
        cards = flow.cards
        left, right = card_span(cards)
        frame(document, cards, base_arrow(flow.axis_y, left, right),
              ((right - left) / 2.0) - AXIS_X)
      end

      def frame(document, cards, axis, title_x)
        Scene.new(
          id: document.id, acc_title: document.accessibility_title,
          acc_description: document.accessibility_description,
          title: document.label, title_x: title_x, title_y: TITLE_Y,
          title_size: TITLE_SIZE, cards: cards, axis: axis
        )
      end

      def card_span(cards)
        return [0, 0] if cards.empty?

        ranges = cards.map(&:x_range)
        [ranges.map(&:first).min, ranges.map(&:last).max]
      end

      def base_arrow(axis_y, left, right)
        TimelineLine.new(
          x1: AXIS_X, y1: axis_y, x2: (right - left) + (3 * AXIS_X),
          y2: axis_y, stroke_width: 4
        )
      end

      # Moves the drawing so its viewBox starts at the origin.
      def shift_to_origin(scene)
        delta_x = FRAME - left_edge(scene)
        delta_y = FRAME - top_edge(scene)
        scene.cards.each { |card| card.shift(delta_x, delta_y) }
        scene.axis.shift(delta_x, delta_y)
        scene.title_x += delta_x
        scene.title_y += delta_y
        size(scene)
      end

      def size(scene)
        width = scene.axis.x2 + FRAME
        height = bottom_edge(scene) + FRAME
        scene.width = width.round(4)
        scene.height = height.round(4)
        scene.view_box = "0 0 #{scene.width} #{scene.height}"
        scene
      end

      def left_edge(scene)
        edges = scene.cards.map { |card| card.x_range.first }
        edges << AXIS_X
        edges << scene.title_x if scene.title
        edges.min
      end

      def top_edge(scene)
        edges = scene.cards.map(&:y) << scene.axis.y1
        edges << (TITLE_Y - TITLE_ASCENT) if scene.title
        edges.min
      end

      def bottom_edge(scene)
        scene.cards.map(&:bottom).push(scene.axis.y1).max
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Timeline.call(diagram)
      end

      def sectioned?(document)
        document.items.any? { |item| item.role == "section" }
      end

      # mmdc draws only the periods inside a section once the diagram has
      # one; periods written before the first section are not drawn.
      def groups(document)
        sections = items(document, "section")
        return [{ name: nil, periods: periods(document, nil) }] if
          sections.empty?

        sections.map do |section|
          { name: section.label, periods: periods(document, section.id) }
        end
      end

      def periods(document, parent_id)
        events = items(document, "event", parent_id).map do |event|
          { name: event_time(event),
            events: items(document, "description", event.id).map(&:label) }
        end
        events + items(document, "task", parent_id).map do |task|
          { name: task.label, events: [] }
        end
      end

      def items(document, role, parent_id = :any)
        document.items.select do |item|
          next false unless item.role == role

          parent_id == :any || item.parent_id == parent_id
        end
      end

      def event_time(event)
        event.placements.find { |item| item.dimension == "time" }.value.value
      end
    end
  end
end
