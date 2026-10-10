# frozen_string_literal: true

require_relative "user_journey_legend"

module Sirena
  module Layout
    # Positions for a user journey scene, copied from mmdc's journey renderer.
    #
    # Task columns are 200px apart (a 150px box and a 50px gap), starting at
    # the legend's left margin. Each run of tasks sharing a section name gets
    # a 50px band above it; tasks hang from y=110 on a dashed line down to
    # y=450 with a face on it at a height set by the score.
    module UserJourneyGeometry
      TASK_WIDTH = 150
      TASK_BOX_HEIGHT = 50
      TASK_PITCH = 200
      SECTION_Y = 50
      TASK_Y = 110
      LINE_END = 450
      FACE_TOP = 300
      FACE_STEP = 30
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

      def scene_from_graph(graph)
        nodes = graph[:children] || []
        legend = UserJourneyLegend.new(graph_actor_names(nodes))
        left = legend.left_margin
        frame = frame_size(left, nodes.length, legend.rows.length, graph)
        UserJourney::Scene.new(
          **scene_header(graph, frame), **scene_body(nodes, legend),
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

      def scene_body(nodes, legend)
        left = legend.left_margin
        runs = section_runs(nodes)
        {
          legend: legend_actors(legend),
          sections: section_bands(runs, left),
          tasks: typed_tasks(nodes, runs, left, legend),
          arrows: [timeline(left, scene_width(left, nodes.length))],
        }
      end

      def graph_actor_names(nodes)
        nodes.flat_map { |node| Array(node.dig(:metadata, :actors)) }
      end

      def frame_size(left, count, actors, graph)
        width = scene_width(left, count)
        stop_y = [actors * LEGEND_ROW_HEIGHT, count.zero? ? 0 : LINE_END].max
        title = graph.dig(:metadata, :title).to_s.empty? ? 0 : TITLE_EXTRA
        height = stop_y + 20 + title
        { width: width, height: height, left: left,
          view_box: "0 -25 #{width} #{height}" }
      end

      def scene_width(left, count)
        stop_x = count.zero? ? left : left + ((count - 1) * TASK_PITCH) + 100
        left + stop_x + DIAGRAM_MARGIN
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

      def section_bands(runs, left)
        runs.reject { |_, name, _| name.empty? }.map do |indexes, name, number|
          style = run_style(number)
          x_position = left + (indexes.first * TASK_PITCH)
          width = (TASK_PITCH * indexes.length) - 50
          section_band(name, [x_position, width], style)
        end
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
      def centered_labels(text, span, vertical)
        lines = text.to_s.split(%r{<br\s*/?>}i, -1)
        centre = box_centre(span, vertical[0])
        lines.each_with_index.map do |line, offset|
          shift = line_shift(offset, lines.length)
          centered_label(line, centre, shift, vertical[1])
        end
      end

      def box_centre(span, top)
        [span[0] + (span[1] / 2.0), top + (TASK_BOX_HEIGHT / 2.0)]
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

      def typed_tasks(nodes, runs, left, legend)
        indexes = legend.rows.to_h { |name, index, *| [name, index] }
        runs.flat_map do |run_indexes, _, number|
          style = run_style(number)
          run_indexes.map do |position|
            typed_task(nodes[position], left + (position * TASK_PITCH),
                       style, indexes)
          end
        end
      end

      def typed_task(node, x_position, style, indexes)
        metadata = node[:metadata] || {}
        span = [x_position, TASK_WIDTH]
        UserJourney::Task.new(
          id: node[:id], number: style[:type], line_end: LINE_END,
          box: band_box(span, TASK_Y, style[:fill]),
          labels: centered_labels(metadata[:name], span,
                                  [TASK_Y, style[:colour]]),
          dots: task_dots(metadata[:actors], x_position, indexes),
          **task_facts(metadata)
        )
      end

      def task_facts(metadata)
        {
          score: metadata[:score] || 3,
          section_name: metadata[:section_name],
          section_index: metadata[:section_index],
        }
      end

      def task_dots(actors, x_position, indexes)
        Array(actors).each_with_index.map do |name, offset|
          actor_dot(name, indexes.fetch(name), x_position + 14 + (offset * 10),
                    TASK_Y)
        end
      end
    end
  end
end
