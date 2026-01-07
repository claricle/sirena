# frozen_string_literal: true

require_relative "../../diagram/gantt"

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Gantt diagram model.
      #
      # Converts the parse tree output from Grammars::Gantt into a
      # fully-formed Diagram::GanttChart object with sections and tasks.
      class Gantt
        # Transform parse tree into Gantt diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::GanttChart] the gantt chart diagram model
        def apply(tree)
          diagram = Diagram::GanttChart.new
          @current_section = nil
          @click_map = {}

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

          # Apply click handlers to tasks
          apply_click_handlers(diagram)

          diagram
        end

        private

        def process_item(diagram, item)
          return unless item.is_a?(Hash)

          process_header(diagram, item) if item.key?(:header)
          process_title(diagram, item) if item.key?(:title)
          process_date_format(diagram, item) if item.key?(:date_format)
          process_axis_format(diagram, item) if item.key?(:axis_format)
          process_tick_interval(diagram, item) if item.key?(:tick_interval)
          process_excludes(diagram, item) if item.key?(:excludes)
          process_today_marker(diagram, item) if item.key?(:today_marker)
          process_acc_title(diagram, item) if item.key?(:acc_title)
          process_acc_descr(diagram, item) if item.key?(:acc_descr)
          process_section(diagram, item) if item.key?(:section)
          process_click(item) if item.key?(:click_id)
          process_task(diagram, item) if item.key?(:task_entry)
        end

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_item(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_header(diagram, item)
          # Header is just the 'gantt' keyword, nothing to extract
        end

        def process_title(diagram, item)
          diagram.title = extract_text(item[:title])
        end

        def process_date_format(diagram, item)
          diagram.date_format = extract_text(item[:date_format])
        end

        def process_axis_format(diagram, item)
          diagram.axis_format = extract_text(item[:axis_format])
        end

        def process_tick_interval(diagram, item)
          diagram.tick_interval = extract_text(item[:tick_interval])
        end

        def process_excludes(diagram, item)
          excludes_text = extract_text(item[:excludes])
          diagram.excludes << excludes_text unless excludes_text.empty?
        end

        def process_today_marker(diagram, item)
          diagram.today_marker = extract_text(item[:today_marker])
        end

        def process_acc_title(diagram, item)
          # Store as metadata (not currently in model)
        end

        def process_acc_descr(diagram, item)
          # Store as metadata (not currently in model)
        end

        def process_section(diagram, item)
          section_name = extract_text(item[:section])
          @current_section = Diagram::GanttSection.new(section_name)
          diagram.sections << @current_section
        end

        def process_click(item)
          click_id = extract_text(item[:click_id])
          if item[:href]
            @click_map[click_id] = { type: :href, value: extract_text(item[:href]) }
          elsif item[:callback]
            @click_map[click_id] = { type: :callback, value: extract_text(item[:callback]) }
          end
        end

        def process_task(diagram, item)
          # Ensure we have a section
          unless @current_section
            @current_section = Diagram::GanttSection.new("Default")
            diagram.sections << @current_section
          end

          task_entry = item[:task_entry]
          task = Diagram::GanttTask.new
          task.description = extract_text(task_entry[:description])

          # Process task details
          if task_entry[:task_details]
            process_task_details(task, task_entry[:task_details])
          end

          @current_section.tasks << task
        end

        def process_task_details(task, details)
          return unless details.is_a?(Hash)

          # Extract tags
          if details[:tags]
            extract_tags(task, details[:tags])
          end

          # Extract task ID
          if details[:id]
            task.id = extract_text(details[:id])
          end

          # Extract timing information
          if details[:start_date]
            task.start_date = extract_text(details[:start_date])
          end

          if details[:end_date]
            task.end_date = extract_text(details[:end_date])
          end

          if details[:duration]
            task.duration = extract_text(details[:duration])
          end

          if details[:after_task]
            task.after_task = extract_text(details[:after_task])
          end

          if details[:until_task]
            task.until_task = extract_text(details[:until_task])
          end
        end

        def extract_tags(task, tags_data)
          tags_array = if tags_data.is_a?(Array)
                         tags_data
                       else
                         [tags_data]
                       end

          tags_array.each do |tag_item|
            tag = extract_text(tag_item)
            task.tags << tag unless tag.empty?
          end
        end

        def apply_click_handlers(diagram)
          diagram.sections.each do |section|
            section.tasks.each do |task|
              next unless task.id && @click_map[task.id]

              click_info = @click_map[task.id]
              if click_info[:type] == :href
                task.click_href = click_info[:value]
              elsif click_info[:type] == :callback
                task.click_callback = click_info[:value]
              end
            end
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