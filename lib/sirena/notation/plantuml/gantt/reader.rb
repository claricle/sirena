# frozen_string_literal: true

require "date"
require_relative "../../../diagram/gantt"
require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Gantt
        # Reads PlantUML gantt source into the Gantt model Sirena already
        # schedules.
        #
        # A task is a `[Name]` followed by clauses: `requires` or `lasts` a
        # duration, `starts at` a date or at another task's end, `ends at` a
        # date, `happens at` a date, or `is N% completed`. `[A] -> [B]` makes
        # B follow A, `then [B] ...` makes B follow the task before it, and
        # `-- Title --` opens a section. A task with no start follows
        # nothing and begins on the project's first day. Weeks count seven
        # days, as PlantUML counts them. A line outside this subset raises
        # {UnsupportedConstructError}.
        class Reader
          DATE = /\d{4}-\d{2}-\d{2}/
          UNIT = /(?:day|week)s?/
          SPAN = /(\d+)[ \t]+(#{UNIT})(?:[ \t]+and[ \t]+(\d+)[ \t]+(#{UNIT}))?/
          REF = /\[([^\]]+)\]/
          PROJECT = /\AProject[ \t]+starts[ \t]+(?:the[ \t]+|on[ \t]+)?
                     (#{DATE})\z/ix
          SECTION = /\A--+[ \t]*(.*?)[ \t]*--+\z/
          ARROW = /\A#{REF}[ \t]*-+>[ \t]*#{REF}\z/
          TASK = /\A(then[ \t]+)?#{REF}(?:[ \t]+as[ \t]+#{REF})?
                   (?:[ \t]+(.*))?\z/ix
          SKIPPED = /\A(?:title|header|footer|caption|legend|skinparam|
                     scale|printscale|ganttscale|language|hide|show|
                     (?:mon|tues|wednes|thurs|fri|satur|sun)day[ \t]+(?:is|are)|
                     #{DATE}[ \t]+is)\b/xi
          CLAUSES = [
            [/\A(?:requires|lasts)[ \t]+#{SPAN}/i, :duration],
            [/\Astarts(?:[ \t]+at|[ \t]+on)?[ \t]+#{REF}'s[ \t]+(start|end)/i,
             :follow],
            [/\Astarts(?:[ \t]+at|[ \t]+on)?[ \t]+(#{DATE})/i, :start],
            [/\Aends(?:[ \t]+at|[ \t]+on)?[ \t]+(#{DATE})/i, :finish],
            [/\Ahappens(?:[ \t]+at|[ \t]+on)?[ \t]+(#{DATE})/i, :happens],
            [/\Ais[ \t]+\d+%[ \t]+complete(?:d)?/i, :ignored],
            [/\Ais[ \t]+colored[ \t]+in[ \t]+\S+/i, :ignored],
          ].freeze
          ANCHOR = "2000-01-01"
          private_constant :DATE, :UNIT, :SPAN, :REF, :PROJECT, :SECTION,
                           :ARROW, :TASK, :SKIPPED, :CLAUSES, :ANCHOR

          # @param source [String] PlantUML source
          # @return [Array(Sirena::Diagram::Gantt, Boolean)] the model, and
          #   whether the source named the project's first day
          # @raise [UnsupportedConstructError] on a line outside the subset
          def parse(source)
            @model = Sirena::Diagram::Gantt.new
            @section = nil
            @tasks = {}
            @last = nil
            @start = nil
            lines(source).each { |text, number| read(text, number) }
            [finish, !@start.nil?]
          end

          private

          def lines(source)
            body = numbered_lines(source).drop_while do |line, _|
              !line.start_with?("@start")
            end
            body.drop(1).take_while { |line, _| !line.start_with?("@end") }
              .reject { |line, _| line.empty? || line.start_with?("'") }
          end

          def numbered_lines(source)
            text = source.dup.force_encoding(Encoding::UTF_8).scrub
            text.lines.map.with_index { |line, index| [line.strip, index + 1] }
          end

          def read(text, number)
            return if SKIPPED.match?(text)
            return @start = PROJECT.match(text)[1] if PROJECT.match?(text)
            return open_section(SECTION.match(text)[1]) if SECTION.match?(text)

            read_task(text, number)
          end

          def read_task(text, number)
            return follow(*ARROW.match(text).captures) if ARROW.match?(text)
            return task(TASK.match(text)) if TASK.match?(text)

            raise UnsupportedConstructError.new(
              construct: "gantt statement", line: number, text: text,
            )
          end

          def open_section(name)
            @section = Sirena::Diagram::GanttSection.new(name)
            @model.sections << @section
          end

          def task(match)
            then_, name, alias_name, rest = match.captures
            current = lookup(name, alias_name)
            current.after_task = @last.id if then_ && @last
            clauses(current, rest.to_s, name)
            @last = current
          end

          def clauses(task, rest, name)
            until rest.empty?
              kind, found = CLAUSES.lazy.filter_map do |pattern, symbol|
                match = pattern.match(rest)
                [symbol, match] if match
              end.first
              raise unsupported(name, rest) unless kind

              apply(task, kind, found)
              rest = found.post_match.sub(/\A[ \t]+(?:and[ \t]+)?/i, "")
            end
          end

          def unsupported(name, rest)
            UnsupportedConstructError.new(
              construct: "gantt clause", line: 0, text: "[#{name}] #{rest}",
            )
          end

          def apply(task, kind, match)
            case kind
            when :duration then task.duration = "#{days(match)}d"
            when :follow then follow_task(task, match)
            when :start then task.start_date = match[1]
            when :finish then finish_on(task, match[1])
            when :happens then happen(task, match[1])
            end
          end

          def days(match)
            first = span_days(match[1], match[2])
            return first unless match[3]

            first + span_days(match[3], match[4])
          end

          def span_days(count, unit)
            count.to_i * (unit.downcase.start_with?("w") ? 7 : 1)
          end

          def follow_task(task, match)
            return add_predecessor(task, lookup(match[1], nil)) if
              match[2].casecmp?("end")

            raise unsupported(task.description,
                              "starts at [#{match[1]}]'s start")
          end

          def finish_on(task, date)
            from = Date.iso8601(task.start_date || @start || ANCHOR)
            span = (Date.iso8601(date) - from).to_i
            task.duration = "#{[span, 0].max}d"
          end

          def happen(task, date)
            task.start_date = date
            task.duration = "0d"
            task.tags << "milestone"
          end

          def follow(from, to)
            add_predecessor(lookup(to, nil), lookup(from, nil))
          end

          def add_predecessor(task, predecessor)
            task.after_task = [task.after_task,
                               predecessor.id].compact.join(" ")
          end

          # Tasks are created on first mention, in a section made on demand.
          def lookup(name, alias_name)
            found = @tasks[name] || @tasks[alias_name]
            found ||= create(name)
            @tasks[alias_name] = found if alias_name
            found
          end

          def create(name)
            open_section(nil) unless @section
            Sirena::Diagram::GanttTask.new.tap do |task|
              task.description = name
              task.id = "task#{@tasks.values.uniq.length + 1}"
              task.duration = "1d"
              @tasks[name] = task
              @section.tasks << task
            end
          end

          # A task with nothing to follow starts on the project's first day.
          def finish
            first = @start || ANCHOR
            @model.sections.flat_map(&:tasks).each do |task|
              task.start_date ||= first unless task.after_task
            end
            @model
          end
        end
      end
    end
  end
end
