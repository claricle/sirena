# frozen_string_literal: true

require_relative "user_journey_legend"
require_relative "user_journey_face_geometry"

module Sirena
  module Layout
    # Positions for a user journey scene, copied from mmdc's journey renderer.
    #
    # Task columns are 200px apart (a 150px box and a 50px gap), starting at
    # the legend's left margin. Each run of tasks sharing a section name gets
    # a 50px band above it; tasks hang from y=110 on a dashed line down to
    # y=450 with a face on it at a height set by the score.
    module UserJourneyGeometry
      include UserJourneyFaceGeometry

      TASK_WIDTH = 150
      TASK_BOX_HEIGHT = 50
      TASK_PITCH = 200
      SECTION_Y = 50
      TASK_Y = 110
      LINE_END = 450
      LEGEND_ROW_HEIGHT = 50
      DIAGRAM_MARGIN = 100
      TITLE_EXTRA = 70
      TIMELINE_Y = 200
      TEXT_SIZE = 14
      NO_SECTION_FILL = "#CCC"
      SECTION_FILLS = %w[
        #191970 #8B008B #4B0082 #2F4F4F #800000 #8B4513 #00008B
      ].freeze
      ACTOR_COLOURS = %w[
        #8FBC8F #7CFC00 #00FFFF #20B2AA #B0E0E6 #FFFFE0
      ].freeze

      private

      def scene_from_graph(graph, positioned: false)
        nodes = graph[:children] || []
        legend = UserJourneyLegend.new(graph_actor_names(nodes))
        left = legend.left_margin
        boxes = task_boxes(nodes, left, positioned)
        frame = frame_size(left, boxes, legend.rows.length, graph)
        UserJourney::Scene.new(
          **scene_header(graph, frame), **scene_body(nodes, boxes, legend),
        )
      end

      def scene_header(graph, frame)
        title = graph.dig(:metadata, :title)
        {
          id: graph[:id] || "user_journey", width: frame[:width],
          height: frame[:height] + 25, view_box: frame[:view_box],
          acc_title: graph.dig(:metadata, :acc_title),
          acc_description: graph.dig(:metadata, :acc_description),
          title: title_label(title, frame[:left])
        }
      end

      def scene_body(nodes, boxes, legend)
        left = legend.left_margin
        runs = section_runs(nodes)
        {
          legend: legend_actors(legend),
          sections: section_bands(runs, boxes),
          tasks: typed_tasks(nodes, boxes, runs, legend),
          arrows: [timeline(left, scene_width(left, boxes))],
        }
      end

      def graph_actor_names(nodes)
        nodes.flat_map { |node| Array(node.dig(:metadata, :actors)) }
      end

      def frame_size(left, boxes, actors, graph)
        width = scene_width(left, boxes)
        stop_y = content_stop_y(boxes, actors)
        title = graph.dig(:metadata, :title).to_s.empty? ? 0 : TITLE_EXTRA
        height = stop_y + 20 + title
        { width: width, height: height, left: left,
          view_box: "0 -25 #{width} #{height}" }
      end

      def content_stop_y(boxes, actors)
        task_bottom = boxes.map { |box| box[:y] + box[:height] }.max || 0
        [actors * LEGEND_ROW_HEIGHT,
         boxes.empty? ? 0 : LINE_END, task_bottom].max
      end

      def scene_width(left, boxes)
        return (left * 2) + DIAGRAM_MARGIN if boxes.empty?

        right = boxes.map { |box| box[:x] + box[:width] }.max
        left + right + (DIAGRAM_MARGIN / 2)
      end

      def task_boxes(nodes, left, positioned)
        return default_task_boxes(nodes, left) unless positioned
        return [] if nodes.empty?

        origin = placement_origin(nodes)
        nodes.map do |node|
          positioned_task_box(node, left, origin)
        end
      end

      def placement_origin(nodes)
        [nodes.map { |node| node.fetch(:x) }.min,
         nodes.map { |node| node.fetch(:y) }.min]
      end

      def positioned_task_box(node, left, origin)
        {
          x: left + node.fetch(:x) - origin[0],
          y: TASK_Y + node.fetch(:y) - origin[1],
          width: node.fetch(:width), height: node.fetch(:height)
        }
      end

      def default_task_boxes(nodes, left)
        nodes.each_index.map do |position|
          {
            x: left + (position * TASK_PITCH), y: TASK_Y,
            width: TASK_WIDTH, height: TASK_BOX_HEIGHT
          }
        end
      end

      def title_label(title, left)
        return if title.to_s.empty?

        UserJourney::Label.new(
          text: title, x: left, y: 25, font_size: 32,
          font_weight: "bold", style: "title"
        )
      end

      def timeline(left, width)
        end_x = width - left - 4
        UserJourney::Arrow.new(
          id: "timeline",
          line: UserJourney::Line.new(
            x1: left, y1: TIMELINE_Y, x2: end_x, y2: TIMELINE_Y,
          ),
          head_path: "M #{end_x - 20},#{TIMELINE_Y - 8} " \
                     "V #{TIMELINE_Y + 8} L #{end_x + 4},#{TIMELINE_Y} Z",
        )
      end

      def legend_actors(legend)
        legend.rows.map do |name, index, row_y, lines|
          UserJourney::Actor.new(
            dot: actor_dot(name, index, 20, row_y),
            labels: legend_labels(lines, row_y),
          )
        end
      end

      def legend_labels(lines, row_y)
        lines.each_with_index.map do |line, offset|
          UserJourney::Label.new(
            text: line, x: 50, y: row_y + 7 + (offset * 20),
            font_size: UserJourneyLegend::FONT_SIZE, style: "legend"
          )
        end
      end

      def actor_dot(name, index, x_position, y_position)
        UserJourney::Dot.new(
          x: x_position, y: y_position, name: name, index: index,
          colour: ACTOR_COLOURS[index % ACTOR_COLOURS.length]
        )
      end

      def section_name(node)
        node.dig(:metadata, :section_name).to_s
      end

      # Consecutive tasks with one section name form a run; [indexes, name,
      # number], number counting the named runs from 0 (nil before the first
      # section, which gets no band).
      def section_runs(nodes)
        runs = nodes.each_index.chunk_while do |first, second|
          section_name(nodes[first]) == section_name(nodes[second])
        end
        named = -1
        runs.map do |indexes|
          name = section_name(nodes[indexes.first])
          [indexes, name, (named += 1 unless name.empty?)]
        end
      end

      def run_style(number)
        return { type: 0, fill: NO_SECTION_FILL, colour: "black" } unless number

        { type: number % SECTION_FILLS.length, colour: "#fff",
          fill: SECTION_FILLS[number % SECTION_FILLS.length] }
      end

      def section_bands(runs, boxes)
        runs.reject { |_, name, _| name.empty? }.map do |indexes, name, number|
          style = run_style(number)
          section_band(name, run_span(indexes, boxes), style)
        end
      end

      def run_span(indexes, boxes)
        selected = indexes.map { |index| boxes.fetch(index) }
        left = selected.map { |box| box[:x] }.min
        right = selected.map { |box| box[:x] + box[:width] }.max
        [left, right - left]
      end

      def section_band(name, span, style)
        UserJourney::Section.new(
          box: band_box(span, SECTION_Y, style[:fill]), number: style[:type],
          labels: centered_labels(name, span, [SECTION_Y, style[:colour]])
        )
      end

      def band_box(span, top, fill)
        UserJourney::Box.new(
          x: span[0], y: top, width: span[1], height: TASK_BOX_HEIGHT,
          corner_radius: 3, fill: fill
        )
      end

      # One label per <br>-separated line, spread around the box centre.
      def centered_labels(text, span, vertical, height: TASK_BOX_HEIGHT)
        lines = text.to_s.split(%r{<br\s*/?>}i, -1)
        centre = box_centre(span, vertical[0], height)
        lines.each_with_index.map do |line, offset|
          shift = line_shift(offset, lines.length)
          centered_label(line, centre, shift, vertical[1])
        end
      end

      def box_centre(span, top, height)
        [span[0] + (span[1] / 2.0), top + (height / 2.0)]
      end

      def centered_label(text, centre, shift, fill)
        UserJourney::Label.new(
          text: text, x: centre[0], y: centre[1] + shift,
          font_size: TEXT_SIZE, text_anchor: "middle", fill: fill
        )
      end

      def line_shift(offset, count)
        (offset * TEXT_SIZE) - (TEXT_SIZE * (count - 1) / 2.0)
      end

      def typed_tasks(nodes, boxes, runs, legend)
        indexes = legend.rows.to_h { |name, index, *| [name, index] }
        runs.flat_map do |run_indexes, _, number|
          style = run_style(number)
          run_indexes.map do |position|
            typed_task(nodes[position], boxes.fetch(position), style, indexes)
          end
        end
      end

      def typed_task(node, geometry, style, indexes)
        metadata = node[:metadata] || {}
        facts = task_facts(metadata)
        UserJourney::Task.new(
          id: node[:id], number: style[:type], line_end: LINE_END,
          dots: task_dots(metadata[:actors], geometry, indexes),
          **task_frame(metadata, geometry, style, facts),
          **facts
        )
      end

      def task_frame(metadata, geometry, style, facts)
        box = UserJourney::Box.new(
          **geometry, corner_radius: 3, fill: style[:fill],
        )
        span = [box.x, box.width]
        {
          box: box, face: task_face(box, facts[:score]),
          labels: centered_labels(metadata[:name], span,
                                  [box.y, style[:colour]], height: box.height)
        }
      end

      def task_facts(metadata)
        {
          score: metadata[:score] || 3,
          section_name: metadata[:section_name],
          section_index: metadata[:section_index],
        }
      end

      def task_dots(actors, geometry, indexes)
        Array(actors).each_with_index.map do |name, offset|
          x_position = geometry[:x] + 14 + (offset * 10)
          actor_dot(name, indexes.fetch(name), x_position, geometry[:y])
        end
      end
    end
  end
end
