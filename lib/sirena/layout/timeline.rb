# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/timeline"

module Sirena
  module Layout
    # Builds final timeline geometry for the SVG renderer.
    class Timeline < Base
      MARGIN_LEFT = 80
      MARGIN_TOP = 100
      MARGIN_RIGHT = 80
      MARGIN_BOTTOM = 60
      TIMELINE_WIDTH = 800
      TIMELINE_HEIGHT = 6
      EVENT_MARKER_RADIUS = 8
      EVENT_LABEL_OFFSET_Y = 35
      SECTION_HEIGHT = 40
      SECTION_SPACING = 20
      TITLE_Y = 40

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
        attribute :section_index, :integer
      end

      class Axis < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
      end

      class Marker < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
        attribute :section_index, :integer
      end

      class Entry < Lutaml::Model::Serializable
        attribute :marker, Marker
        attribute :labels, Label, collection: true, default: -> { [] }
      end

      class Track < Lutaml::Model::Serializable
        attribute :header, Label
        attribute :axis, Axis
        attribute :entries, Entry, collection: true, default: -> { [] }
        attribute :range_labels, Label, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :title, Label
        attribute :tracks, Track, collection: true, default: -> { [] }
      end

      # Retains the pre-Scene structure for direct callers during conversion.
      def build_graph(diagram)
        all_events = collect_all_events(diagram)
        timeline_range = calculate_timeline_range(all_events)

        {
          id: "timeline",
          title: diagram.title,
          acc_title: diagram.acc_title,
          acc_description: diagram.acc_description,
          sections: transform_sections(diagram, timeline_range),
          events: transform_events(diagram.events, timeline_range),
          timeline: timeline_range,
          metadata: {
            section_count: diagram.sections.length,
            total_events: all_events.length,
            has_sections: diagram.has_sections?,
          },
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        width = MARGIN_LEFT + TIMELINE_WIDTH + MARGIN_RIGHT
        height = scene_height(graph)

        Scene.new(
          id: graph[:id], width: width, height: height,
          view_box: "0 0 #{width} #{height}",
          title: title_label(graph[:title]), tracks: tracks(graph)
        )
      end

      def scene_height(graph)
        height = MARGIN_TOP + MARGIN_BOTTOM + 100
        return height unless graph.dig(:metadata, :has_sections)

        height + (graph[:sections].length * (SECTION_HEIGHT + SECTION_SPACING))
      end

      def title_label(title)
        return unless title

        label(title, MARGIN_LEFT + (TIMELINE_WIDTH / 2), TITLE_Y,
              font_size(:font_size_large, 18), style: "title",
                                               anchor: "middle", weight: "bold")
      end

      def tracks(graph)
        return [simple_track(graph)] unless graph.dig(:metadata, :has_sections)

        graph[:sections].map.with_index do |section, index|
          section_track(section, graph[:timeline], index)
        end
      end

      def simple_track(graph)
        Track.new(
          axis: axis(MARGIN_TOP), entries: event_entries(graph[:events], MARGIN_TOP, 0),
          range_labels: range_labels(graph[:timeline], MARGIN_TOP)
        )
      end

      def section_track(section, timeline, index)
        header_y = MARGIN_TOP + (index * (SECTION_HEIGHT + SECTION_SPACING))
        axis_y = header_y + SECTION_HEIGHT
        entries = if section[:has_events]
                    event_entries(section[:events], axis_y, index)
                  elsif section[:has_tasks]
                    task_entries(section[:tasks], axis_y, index)
                  else
                    []
                  end

        Track.new(
          header: label(section[:name], MARGIN_LEFT, header_y,
                        font_size(:font_size_normal, 14), style: "section",
                                                          weight: "bold", section_index: index),
          axis: axis(axis_y), entries: entries,
          range_labels: index.zero? ? range_labels(timeline, axis_y) : []
        )
      end

      def axis(y)
        Axis.new(
          x: MARGIN_LEFT, y: y, width: TIMELINE_WIDTH,
          height: TIMELINE_HEIGHT, corner_radius: TIMELINE_HEIGHT / 2.0
        )
      end

      def event_entries(events, y, section_index)
        events.map do |event|
          x = event_x(event[:x_position])
          labels = event[:descriptions].map.with_index do |description, index|
            label(description.to_s.strip, x,
                  y + EVENT_LABEL_OFFSET_Y + (index * 16),
                  font_size(:font_size_small, 11), style: "event",
                                                   anchor: "middle")
          end
          labels << label(event[:time].to_s, x, y - 15,
                          font_size(:font_size_small, 10), style: "muted",
                                                           anchor: "middle", weight: "bold")
          Entry.new(marker: marker(x, y, section_index), labels: labels)
        end
      end

      def task_entries(tasks, y, section_index)
        return [] if tasks.empty?

        spacing = TIMELINE_WIDTH / (tasks.length + 1).to_f
        tasks.map.with_index do |task, index|
          x = MARGIN_LEFT + (spacing * (index + 1))
          task_label = label(task.to_s, x, y + EVENT_LABEL_OFFSET_Y,
                             font_size(:font_size_small, 11), style: "event",
                                                              anchor: "middle")
          Entry.new(marker: marker(x, y, section_index), labels: [task_label])
        end
      end

      def marker(x, y, section_index)
        Marker.new(
          x: x, y: y + (TIMELINE_HEIGHT / 2.0),
          radius: EVENT_MARKER_RADIUS, section_index: section_index
        )
      end

      def range_labels(timeline, y)
        return [] unless timeline

        min = timeline[:min]
        max = timeline[:max]
        middle = ((min + max) / 2.0).round
        label_y = y + TIMELINE_HEIGHT + 20
        [[min, MARGIN_LEFT], [max, MARGIN_LEFT + TIMELINE_WIDTH],
         [middle, MARGIN_LEFT + (TIMELINE_WIDTH / 2)]].map do |text, x|
          label(text.to_s, x, label_y, font_size(:font_size_small, 10),
                style: "muted", anchor: "middle")
        end
      end

      def label(text, x, y, size, **options)
        Label.new(
          text: text, x: x, y: y, font_size: size,
          text_anchor: options[:anchor], font_weight: options[:weight],
          style: options.fetch(:style), section_index: options[:section_index]
        )
      end

      def font_size(name, fallback)
        value = theme.typography&.public_send(name)
        value&.positive? ? value : fallback
      end

      def event_x(x_position)
        MARGIN_LEFT + ((x_position / 100.0) * TIMELINE_WIDTH)
      end

      def collect_all_events(diagram)
        diagram.sections.each_with_object(diagram.events.dup) do |section, events|
          events.concat(section.events)
        end
      end

      def calculate_timeline_range(events)
        return default_timeline_range if events.empty?

        time_values = events.filter_map { |event| extract_numeric_time(event.time) }
        return default_timeline_range if time_values.empty?

        min_time = time_values.min
        max_time = time_values.max
        padding = [((max_time - min_time) * 0.1).ceil, 1].max
        {
          min: min_time - padding,
          max: max_time + padding,
          span: (max_time - min_time) + (2 * padding),
        }
      end

      def default_timeline_range
        { min: 2000, max: 2024, span: 24 }
      end

      def extract_numeric_time(time_string)
        return if time_string.nil? || time_string.empty?

        match = time_string.match(/\d+/)
        match&.then { |value| value[0].to_i }
      end

      def transform_sections(diagram, timeline_range)
        diagram.sections.map.with_index do |section, index|
          {
            id: "section_#{index}", name: section.name,
            events: transform_events(section.events, timeline_range),
            tasks: section.tasks, has_events: section.has_events?,
            has_tasks: section.has_tasks?
          }
        end
      end

      def transform_events(events, timeline_range)
        events.map.with_index do |event, index|
          {
            id: "event_#{index}", time: event.time,
            descriptions: event.descriptions,
            primary_description: event.primary_description,
            multiple_descriptions: event.multiple_descriptions?,
            x_position: calculate_x_position(event.time, timeline_range)
          }
        end
      end

      def calculate_x_position(time_string, timeline_range)
        numeric_time = extract_numeric_time(time_string)
        return 0 unless numeric_time
        return 50.0 unless timeline_range[:span].positive?

        ((numeric_time - timeline_range[:min]).to_f / timeline_range[:span]) * 100.0
      end
    end
  end
end
