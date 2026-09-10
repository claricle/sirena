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
        TAG_KEYWORDS = %w[done active crit milestone].freeze
        DURATION_PATTERN = /\A\d+[dwMh]\z/
        DATE_PATTERN = %r{\A\d+[-/:][\d\-/:]*\z}
        private_constant :TAG_KEYWORDS, :DURATION_PATTERN, :DATE_PATTERN

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

        # Task details are a comma-separated list of fields with no fixed
        # position (mermaid allows tags, an id, "after"/"until", a date, and
        # a duration in any order). Tags are unambiguous keywords, consumed
        # first regardless of position. What is left occupies id/start/end —
        # THREE positional slots — and mermaid classifies by POSITION when
        # there are exactly three (the id is always first, even when its
        # text happens to look like a date, corpus gantt/NNN), and by shape
        # otherwise. An "after"/"until" dependency fills the start slot the
        # same as a bare date would, so it must still count towards that
        # three-slot rule; only once the id is settled does it get stripped
        # out on its own.
        def process_task_details(task, details)
          return unless details.is_a?(Hash)

          fields = extract_task_fields(details[:parts])
          positional_fields = reject_tag_fields(task, fields)
          task.id = positional_fields.shift if positional_fields.length == 3

          value_fields = reject_dependency_fields(task, positional_fields)

          dates = []
          value_fields.each { |field| classify_value_field(task, field, dates) }
          assign_dates(task, dates)
        end

        def extract_task_fields(parts)
          Array(parts.is_a?(Array) ? parts : [parts]).map { |part| extract_text(part[:field]) }
        end

        def reject_tag_fields(task, fields)
          fields.reject do |field|
            next false unless TAG_KEYWORDS.include?(field)

            task.tags << field
            true
          end
        end

        def reject_dependency_fields(task, fields)
          fields.reject do |field|
            case field
            when /\Aafter\s+(.+)\z/
              task.after_task = Regexp.last_match(1)
              true
            when /\Auntil\s+(.+)\z/
              task.until_task = Regexp.last_match(1)
              true
            end
          end
        end

        def classify_value_field(task, field, dates)
          case field
          when DURATION_PATTERN
            task.duration = field
          when DATE_PATTERN
            dates << field
          else
            task.id = field
          end
        end

        # A lone date is normally the start. After an "after" dependency,
        # though, the dependency supplies the start (see
        # GanttTransform#resolve_task_dependency, which reads calculated
        # start from the referenced task and never consults `start_date`
        # once `after_task` is set) — so a single trailing date there is the
        # end, or `resolve_task_dependency` never finds an end to compute.
        def assign_dates(task, dates)
          if dates.length == 1 && task.after_task
            task.end_date = dates[0]
          else
            task.start_date = dates[0] if dates[0]
            task.end_date = dates[1] if dates[1]
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