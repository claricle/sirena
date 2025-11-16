# frozen_string_literal: true

require_relative "../../diagram/timeline"

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Timeline diagram model.
      #
      # Converts the parse tree output from Grammars::Timeline into a
      # fully-formed Diagram::Timeline object with sections and events.
      class Timeline
        # Transform parse tree into Timeline diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Timeline] the timeline diagram model
        def apply(tree)
          diagram = Diagram::Timeline.new
          @current_section = nil
          @last_event = nil

          # Tree structure: array with header and statements
          if tree.is_a?(Array)
            tree.each do |item|
              next unless item.is_a?(Hash)

              process_item(diagram, item)
            end
          elsif tree.is_a?(Hash)
            process_item(diagram, tree)

            if tree[:statements]
              process_statements(diagram, tree[:statements])
            end
          end

          diagram
        end

        private

        def process_item(diagram, item)
          return unless item.is_a?(Hash)

          process_header(diagram, item) if item.key?(:header)
          process_title(diagram, item) if item.key?(:title)
          process_acc_title(diagram, item) if item.key?(:acc_title)
          process_acc_descr(diagram, item) if item.key?(:acc_descr)
          process_section(diagram, item) if item.key?(:section)
          process_event(diagram, item) if item.key?(:event_entry)
          process_continuation(diagram, item) if item.key?(:continuation_entry)
          process_task(diagram, item) if item.key?(:task)
        end

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_item(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_header(diagram, item)
          # Header is just the 'timeline' keyword, nothing to extract
        end

        def process_title(diagram, item)
          diagram.title = extract_text(item[:title])
        end

        def process_acc_title(diagram, item)
          diagram.acc_title = extract_text(item[:acc_title])
        end

        def process_acc_descr(diagram, item)
          diagram.acc_description = extract_text(item[:acc_descr])
        end

        def process_section(diagram, item)
          section_name = extract_text(item[:section])
          @current_section = Diagram::TimelineSection.new(section_name)
          diagram.sections << @current_section
          @last_event = nil
        end

        def process_event(diagram, item)
          event_data = item[:event_entry]
          return unless event_data

          time = extract_text(event_data[:time])
          descriptions = extract_descriptions(event_data[:descriptions])

          event = Diagram::TimelineEvent.new.tap do |e|
            e.time = time
            e.descriptions.concat(descriptions)
          end

          # Store reference for continuation entries
          @last_event = event

          # Add to current section or diagram
          if @current_section
            @current_section.events << event
          else
            diagram.events << event
          end
        end

        def process_continuation(diagram, item)
          continuation_data = item[:continuation_entry]
          return unless continuation_data

          descriptions = extract_descriptions(continuation_data[:descriptions])

          # Add descriptions to last event if it exists
          if @last_event
            @last_event.descriptions.concat(descriptions)
          else
            # If no last event, create a new event with empty time
            # This handles edge case of continuation at start
            event = Diagram::TimelineEvent.new.tap do |e|
              e.time = ""
              e.descriptions.concat(descriptions)
            end

            if @current_section
              @current_section.events << event
            else
              diagram.events << event
            end

            @last_event = event
          end
        end

        def process_task(diagram, item)
          # Ensure we have a section for tasks
          unless @current_section
            @current_section = Diagram::TimelineSection.new("Default")
            diagram.sections << @current_section
          end

          task_name = extract_text(item[:task])
          @current_section.tasks << task_name unless task_name.empty?
        end

        def extract_descriptions(descriptions_data)
          return [] unless descriptions_data

          # descriptions_data is an array of {:desc => text} hashes
          if descriptions_data.is_a?(Array)
            descriptions_data.map do |item|
              if item.is_a?(Hash) && item[:desc]
                extract_text(item[:desc])
              else
                extract_text(item)
              end
            end.reject(&:empty?)
          elsif descriptions_data.is_a?(Hash) && descriptions_data[:desc]
            [extract_text(descriptions_data[:desc])].reject(&:empty?)
          else
            [extract_text(descriptions_data)].reject(&:empty?)
          end
        end

        def extract_text(value)
          case value
          when Hash
            value.values.first.to_s
          when String
            value
          else
            value.to_s
          end.strip
        end
      end
    end
  end
end