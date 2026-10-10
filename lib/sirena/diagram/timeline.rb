# frozen_string_literal: true

require "lutaml/model"
require_relative "base"

module Sirena
  module Diagram
    # Represents an event in a timeline.
    #
    # An event represents a point in time with associated description(s).
    # Events can have multiple descriptions (when multiple things happened
    # at the same time).
    class TimelineEvent < Lutaml::Model::Serializable
      # The time/date/year for this event
      attribute :time, :string

      # Event descriptions (can be multiple for same time)
      attribute :descriptions, :string, collection: true, default: -> { [] }

      # Validates the event has required attributes.
      #
      # @return [Boolean] true if event is valid
      def valid?
        !time.nil? && !time.empty? && !descriptions.empty?
      end

      # Get primary description (first one).
      #
      # @return [String, nil] the first description or nil
      def primary_description
        descriptions.first
      end

      # A period written without descriptions (a bare task line).
      #
      # @return [Boolean] true if there are no descriptions
      def bare?
        descriptions.empty?
      end

      # Check if event has multiple descriptions.
      #
      # @return [Boolean] true if more than one description
      def multiple_descriptions?
        descriptions.size > 1
      end
    end

    # Represents a section/period in a timeline.
    #
    # A section groups related events together, typically representing
    # a period, category, or theme.
    class TimelineSection < Lutaml::Model::Serializable
      # Name/title of this section
      attribute :name, :string

      # Periods in source order: events and bare tasks interleaved as
      # written. A bare task is an event without descriptions.
      attribute :events, TimelineEvent, collection: true,
                                        default: -> { [] }

      def initialize(name = nil)
        super()
        @name = name
        @events = []
      end

      # Names of the bare tasks, in source order.
      #
      # @return [Array<String>] task names
      def tasks
        events.select(&:bare?).map(&:time)
      end

      # Validates the section.
      #
      # @return [Boolean] true if section has a name
      def valid?
        !name.nil? && !name.empty?
      end

      # Check if section has events.
      #
      # @return [Boolean] true if section has events with descriptions
      def has_events?
        events.any? { |event| !event.bare? }
      end

      # Check if section has tasks.
      #
      # @return [Boolean] true if section has tasks
      def has_tasks?
        events.any?(&:bare?)
      end
    end

    # Timeline diagram model.
    #
    # Represents a timeline showing chronological events, optionally
    # grouped into sections. Timelines are useful for showing historical
    # progression, project milestones, or any time-based sequence.
    #
    # @example Creating a simple timeline
    #   timeline = Timeline.new
    #   timeline.title = 'History of Computing'
    #
    #   section = TimelineSection.new('Early Era')
    #   event = TimelineEvent.new
    #   event.time = '1936'
    #   event.descriptions << 'Turing machine'
    #   section.events << event
    #
    #   timeline.sections << section
    class Timeline < Base
      # Collection of sections in the timeline
      attribute :sections, TimelineSection, collection: true,
                                            default: -> { [] }

      # Periods (events and bare tasks, in source order) written before
      # the first section
      attribute :events, TimelineEvent, collection: true,
                                        default: -> { [] }

      # Accessibility title (for screen readers)
      attribute :acc_title, :string

      # Accessibility description (for screen readers)
      attribute :acc_description, :string

      def initialize
        @sections = []
        @events = []
        super
      end

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :timeline
      def diagram_type
        :timeline
      end

      # Validates the timeline structure.
      #
      # A timeline is always valid (can be empty for parsing tests).
      # In practice, useful timelines would have events or sections.
      #
      # @return [Boolean] true if timeline is valid
      def valid?
        true
      end

      # Check if timeline has any events.
      #
      # @return [Boolean] true if has events (in sections or standalone)
      def has_events?
        events.any? { |event| !event.bare? } || sections.any?(&:has_events?)
      end

      # Check if timeline has sections.
      #
      # @return [Boolean] true if has sections
      def has_sections?
        !sections.empty?
      end

      # Get all events across all sections and standalone.
      #
      # @return [Array<TimelineEvent>] all events
      def all_events
        section_events = sections.flat_map(&:events)
        events + section_events
      end

      # Get all unique time values from events.
      #
      # @return [Array<String>] sorted array of unique times
      def all_times
        all_events.map(&:time).uniq.sort
      end
    end
  end
end
