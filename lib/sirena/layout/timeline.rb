# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/timeline"
require_relative "../notation/mermaid/ir_adapters/timeline"

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
        attribute :acc_title, :string
        attribute :acc_description, :string
        attribute :title, Label
        attribute :tracks, Track, collection: true, default: -> { [] }
      end

      # Retains the pre-Scene structure for direct callers during conversion.
      def build_graph(diagram)
        document = ir_document(diagram)
        all_events = collect_all_events(document)
        timeline_range = calculate_timeline_range(all_events)

        {
          id: document.id,
          title: document.label,
          acc_title: document.accessibility_title,
          acc_description: document.accessibility_description,
          sections: transform_sections(document, timeline_range),
          events: transform_events(root_events(document), document,
                                   timeline_range),
          timeline: timeline_range,
          metadata: timeline_metadata(document, all_events),
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
          acc_title: graph[:acc_title],
          acc_description: graph[:acc_description],
          title: title_label(graph[:title]), tracks: tracks(graph)
        )
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Timeline.call(diagram)
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
          axis: axis(MARGIN_TOP),
          entries: event_entries(graph[:events], MARGIN_TOP, 0),
          range_labels: range_labels(graph[:timeline], MARGIN_TOP),
        )
      end

      def section_track(section, timeline, index)
        header_y = MARGIN_TOP + (index * (SECTION_HEIGHT + SECTION_SPACING))
        axis_y = header_y + SECTION_HEIGHT

        Track.new(
          header: section_header(section, header_y, index),
          axis: axis(axis_y), entries: section_entries(section, axis_y, index),
          range_labels: index.zero? ? range_labels(timeline, axis_y) : []
        )
      end

      def section_header(section, y_position, section_index)
        label(
          section[:name], MARGIN_LEFT, y_position,
          font_size(:font_size_normal, 14), style: "section",
                                            weight: "bold", section_index: section_index
        )
      end

      def section_entries(section, y_position, section_index)
        if section[:has_events]
          return event_entries(section[:events], y_position, section_index)
        end
        if section[:has_tasks]
          return task_entries(section[:tasks], y_position, section_index)
        end

        []
      end

      def axis(y_position)
        Axis.new(
          x: MARGIN_LEFT, y: y_position, width: TIMELINE_WIDTH,
          height: TIMELINE_HEIGHT, corner_radius: TIMELINE_HEIGHT / 2.0
        )
      end

      def event_entries(events, y_position, section_index)
        events.map do |event|
          event_entry(event, y_position, section_index)
        end
      end

      def event_entry(event, y_position, section_index)
        x_position = event_x(event[:x_position])
        Entry.new(
          marker: marker(x_position, y_position, section_index),
          labels: event_labels(event, x_position, y_position),
        )
      end

      def event_labels(event, x_position, y_position)
        descriptions = event[:descriptions].map.with_index do |description, index|
          event_description(description, x_position, y_position, index)
        end
        descriptions << event_time_label(event, x_position, y_position)
      end

      def event_description(description, x_position, y_position, index)
        label(
          description.to_s.strip, x_position,
          y_position + EVENT_LABEL_OFFSET_Y + (index * 16),
          font_size(:font_size_small, 11), style: "event", anchor: "middle"
        )
      end

      def event_time_label(event, x_position, y_position)
        label(
          event[:time].to_s, x_position, y_position - 15,
          font_size(:font_size_small, 10), style: "muted",
                                           anchor: "middle", weight: "bold"
        )
      end

      def task_entries(tasks, y_position, section_index)
        return [] if tasks.empty?

        spacing = TIMELINE_WIDTH / (tasks.length + 1).to_f
        tasks.map.with_index do |task, index|
          task_entry(task, index, spacing, y_position, section_index)
        end
      end

      def task_entry(task, index, spacing, y_position, section_index)
        x_position = MARGIN_LEFT + (spacing * (index + 1))
        task_label = label(
          task.to_s, x_position, y_position + EVENT_LABEL_OFFSET_Y,
          font_size(:font_size_small, 11), style: "event", anchor: "middle"
        )
        Entry.new(
          marker: marker(x_position, y_position, section_index),
          labels: [task_label],
        )
      end

      def marker(x_position, y_position, section_index)
        Marker.new(
          x: x_position, y: y_position + (TIMELINE_HEIGHT / 2.0),
          radius: EVENT_MARKER_RADIUS, section_index: section_index
        )
      end

      def range_labels(timeline, y_position)
        return [] unless timeline

        range_label_positions(timeline).map do |text, x_position|
          label(text.to_s, x_position, y_position + TIMELINE_HEIGHT + 20,
                font_size(:font_size_small, 10),
                style: "muted", anchor: "middle")
        end
      end

      def range_label_positions(timeline)
        minimum = timeline[:min]
        maximum = timeline[:max]
        middle = ((minimum + maximum) / 2.0).round
        [[minimum, MARGIN_LEFT], [maximum, MARGIN_LEFT + TIMELINE_WIDTH],
         [middle, MARGIN_LEFT + (TIMELINE_WIDTH / 2)]]
      end

      def label(text, x_position, y_position, size, **options)
        Label.new(
          text: text, x: x_position, y: y_position, font_size: size,
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

      def collect_all_events(document)
        document.items.select { |item| item.role == "event" }
      end

      def root_events(document)
        collect_all_events(document).select { |event| event.parent_id.nil? }
      end

      def calculate_timeline_range(events)
        return default_timeline_range if events.empty?

        time_values = numeric_times(events)
        return default_timeline_range if time_values.empty?

        padded_timeline_range(time_values.min, time_values.max)
      end

      def numeric_times(events)
        events.filter_map do |event|
          extract_numeric_time(event_time(event))
        end
      end

      def padded_timeline_range(min_time, max_time)
        span = max_time - min_time
        padding = [(span * 0.1).ceil, 1].max
        {
          min: min_time - padding,
          max: max_time + padding,
          span: span + (2 * padding),
        }
      end

      def timeline_metadata(document, all_events)
        sections = document.items.select { |item| item.role == "section" }
        {
          section_count: sections.length,
          total_events: all_events.length,
          has_sections: !sections.empty?,
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

      def transform_sections(document, timeline_range)
        section_items(document).map do |section|
          events, tasks = section_contents(document, section)
          transformed = transform_events(events, document, timeline_range)
          section_attributes(section, transformed, tasks)
        end
      end

      def section_items(document)
        document.items.select { |item| item.role == "section" }
      end

      def section_contents(document, section)
        [children(document, section.id, "event"),
         children(document, section.id, "task")]
      end

      def section_attributes(section, events, tasks)
        {
          id: section.id, name: section.label, events: events,
          tasks: tasks.map(&:label), has_events: !events.empty?,
          has_tasks: !tasks.empty?
        }
      end

      def transform_events(events, document, timeline_range)
        events.map do |event|
          descriptions = children(document, event.id, "description")
            .map(&:label)
          time = event_time(event)
          event_attributes(event, time, descriptions, timeline_range)
        end
      end

      def event_attributes(event, time, descriptions, timeline_range)
        {
          id: event.id, time: time, descriptions: descriptions,
          primary_description: descriptions.first,
          multiple_descriptions: descriptions.length > 1,
          x_position: calculate_x_position(time, timeline_range)
        }
      end

      def children(document, parent_id, role)
        document.items.select do |item|
          item.parent_id == parent_id && item.role == role
        end
      end

      def event_time(event)
        placement = event.placements.find do |item|
          item.dimension == "time"
        end
        placement.value.value
      end

      def calculate_x_position(time_string, timeline_range)
        numeric_time = extract_numeric_time(time_string)
        return 0 unless numeric_time
        return 50.0 unless timeline_range[:span].positive?

        offset = numeric_time - timeline_range[:min]
        (offset.to_f / timeline_range[:span]) * 100.0
      end
    end
  end
end
