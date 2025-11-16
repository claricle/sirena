# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/timeline"

module Sirena
  module Transform
    # Timeline transformer for converting timeline models to renderable structure.
    #
    # Handles chronological ordering, positioning along the timeline axis,
    # and grouping by sections.
    #
    # @example Transform a timeline
    #   transform = TimelineTransform.new
    #   data = transform.to_graph(timeline_diagram)
    class TimelineTransform < Base
      # Converts a Timeline diagram to a layout structure with calculated positions.
      #
      # @param diagram [Diagram::Timeline] the timeline diagram to transform
      # @return [Hash] data structure for rendering
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, "Invalid diagram" unless diagram.valid?

        @diagram = diagram

        # Collect all events and determine timeline bounds
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
            has_sections: diagram.has_sections?
          }
        }
      end

      private

      def collect_all_events(diagram)
        events = diagram.events.dup
        diagram.sections.each do |section|
          events.concat(section.events)
        end
        events
      end

      def calculate_timeline_range(events)
        return default_timeline_range if events.empty?

        # Extract numeric time values for positioning
        time_values = events.map { |e| extract_numeric_time(e.time) }.compact

        if time_values.empty?
          return default_timeline_range
        end

        min_time = time_values.min
        max_time = time_values.max

        # Add some padding
        padding = ((max_time - min_time) * 0.1).ceil
        padding = 1 if padding < 1

        {
          min: min_time - padding,
          max: max_time + padding,
          span: (max_time - min_time) + (2 * padding)
        }
      end

      def default_timeline_range
        {
          min: 2000,
          max: 2024,
          span: 24
        }
      end

      def extract_numeric_time(time_str)
        # Try to extract a numeric value from the time string
        # This handles years (2004), dates (2004-01-01), etc.
        return nil if time_str.nil? || time_str.empty?

        # Extract first continuous sequence of digits
        match = time_str.match(/\d+/)
        match ? match[0].to_i : nil
      end

      def transform_sections(diagram, timeline_range)
        diagram.sections.map.with_index do |section, index|
          {
            id: "section_#{index}",
            name: section.name,
            events: transform_events(section.events, timeline_range),
            tasks: section.tasks,
            has_events: section.has_events?,
            has_tasks: section.has_tasks?
          }
        end
      end

      def transform_events(events, timeline_range)
        events.map.with_index do |event, index|
          {
            id: "event_#{index}",
            time: event.time,
            descriptions: event.descriptions,
            primary_description: event.primary_description,
            multiple_descriptions: event.multiple_descriptions?,
            x_position: calculate_x_position(event.time, timeline_range)
          }
        end
      end

      def calculate_x_position(time_str, timeline_range)
        numeric_time = extract_numeric_time(time_str)
        return 0 unless numeric_time

        # Calculate position as percentage along timeline
        # This will be scaled by renderer to actual coordinates
        if timeline_range[:span] > 0
          ((numeric_time - timeline_range[:min]).to_f / timeline_range[:span]) * 100.0
        else
          50.0 # Center if no span
        end
      end
    end
  end
end