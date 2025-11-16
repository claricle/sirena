# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # Gantt chart task
    class GanttTask < Lutaml::Model::Serializable
      attribute :description, :string
      attribute :id, :string
      attribute :start_date, :string
      attribute :end_date, :string
      attribute :duration, :string
      attribute :after_task, :string
      attribute :until_task, :string
      attribute :tags, :string, collection: true
      attribute :click_href, :string
      attribute :click_callback, :string

      def initialize
        super
        @tags ||= []
      end

      def done?
        tags.include?("done")
      end

      def active?
        tags.include?("active")
      end

      def critical?
        tags.include?("crit")
      end

      def milestone?
        tags.include?("milestone")
      end
    end

    # Gantt chart section grouping
    class GanttSection < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :tasks, GanttTask, collection: true

      def initialize(name = nil)
        super()
        @name = name
        @tasks ||= []
      end
    end

    # Gantt chart diagram model
    class GanttChart < Lutaml::Model::Serializable
      attribute :title, :string
      attribute :date_format, :string, default: -> { "YYYY-MM-DD" }
      attribute :axis_format, :string
      attribute :tick_interval, :string
      attribute :excludes, :string, collection: true
      attribute :today_marker, :string
      attribute :sections, GanttSection, collection: true

      def initialize
        super
        @sections ||= []
        @excludes ||= []
      end
    end
  end
end