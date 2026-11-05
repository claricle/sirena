# frozen_string_literal: true

require_relative "../../../layout/gantt"

module Sirena
  module Notation
    module PlantUML
      module Gantt
        # What a PlantUML gantt layout hands its renderer: a grid of numbered
        # days with the tasks as bars on it, and for a dated project a table
        # of start, end and duration beside it.
        class Scene < Sirena::Layout::Gantt::Scene
          attribute :grid_lines, Sirena::Layout::Gantt::Line,
                    collection: true, default: -> { [] }
          attribute :rules, Sirena::Layout::Gantt::Line,
                    collection: true, default: -> { [] }
          attribute :bars, Sirena::Layout::Gantt::Rect,
                    collection: true, default: -> { [] }
          attribute :diamonds, :string, collection: true, default: -> { [] }
          attribute :texts, Sirena::Layout::Gantt::Label,
                    collection: true, default: -> { [] }
        end

        # PlantUML's gantt layout. The Mermaid layout it extends schedules
        # the tasks (durations, dependencies, start dates); this one counts
        # the days from the first, the way PlantUML does, and sets them in
        # PlantUML's table-and-grid frame.
        class Layout < Sirena::Layout::Gantt
          HEADER = 16.0
          BAR = 12.955
          REACH = BAR / 2
          ROW = BAR + 4.0
          SECTION_ROW = ROW + 16.0
          DAY = 16.0
          CELL_PAD = 10.0
          TABLE_FONT = 10.0
          TASK_FONT = 11.0
          COLUMNS = %w[Start End Duration].freeze
          Row = Struct.new(:kind, :task, :name)
          private_constant :HEADER, :BAR, :REACH, :ROW, :SECTION_ROW, :DAY,
                           :CELL_PAD, :TABLE_FONT, :TASK_FONT, :COLUMNS, :Row

          private

          def scene(diagram)
            graph = build_graph(diagram)
            @dated = graph[:axis_format] == "dated"
            rows = rows_of(graph[:sections])
            tasks = rows.select { |row| row.kind == :task }.map(&:task)
            schedule(tasks)
            frame(rows, tasks)
          end

          def schedule(tasks)
            @anchor = tasks.map { |task| task[:start_date] }.min
            @days = [tasks.map { |task| last_day(task) }.max.to_i, 1].max
          end

          def rows_of(sections)
            sections.flat_map do |section|
              head = if section[:name].to_s.empty?
                       []
                     else
                       [Row.new(:section, nil,
                                section[:name])]
                     end
              head + section[:tasks].map { |task| Row.new(:task, task, nil) }
            end
          end

          def first_day(task)
            (task[:start_date] - @anchor).to_i + 1
          end

          def last_day(task)
            return first_day(task) if task[:milestone]

            [(task[:end_date] - @anchor).to_i, first_day(task)].max
          end

          def cells(task)
            first = first_day(task)
            last = last_day(task)
            length = task[:milestone] ? 0 : last - first + 1
            [boundary(task[:start_date], first),
             boundary(task[:end_date] - (task[:milestone] ? 0 : 1), last),
             "#{length} #{length == 1 ? 'day' : 'days'}"]
          end

          def boundary(date, day)
            @dated ? date.iso8601 : "Day #{day}"
          end

          def frame(rows, tasks)
            table = tasks.map { |task| cells(task) }
            widths = @dated ? column_widths(table) : []
            @origin = widths.sum
            geometry(rows, table, widths)
          end

          def column_widths(table)
            COLUMNS.each_with_index.map do |title, index|
              contents = [title] + table.map { |cells| cells[index] }
              widest = contents.map do |content|
                measure_text(content, font_size: TABLE_FONT)[:width]
              end.max
              widest + CELL_PAD
            end
          end

          def geometry(rows, table, widths)
            @body = HEADER
            @lines = []
            @rules = []
            @bars = []
            @diamonds = []
            @texts = header_texts(widths)
            table_rows = table.each
            rows.each { |row| place(row, widths, table_rows) }
            finish(widths)
          end

          def header_texts(widths)
            columns = widths.each_index.map do |index|
              text(COLUMNS[index], column_left(widths, index) + 5, 11.779,
                   TABLE_FONT)
            end
            columns + day_labels(9.668)
          end

          def day_labels(y_position)
            (1..@days).map do |day|
              measured = measure_text(day.to_s, font_size: TABLE_FONT)[:width]
              left = @origin + ((day - 1) * DAY) + ((DAY - measured) / 2)
              text(day.to_s, left, y_position, TABLE_FONT)
            end
          end

          def column_left(widths, index)
            widths.first(index).sum
          end

          def text(content, x_position, y_position, size, anchor = "start")
            Sirena::Layout::Gantt::Label.new(
              text: content, x: x_position, y: y_position,
              text_anchor: anchor, font_size: size
            )
          end

          def place(row, widths, table_rows)
            return place_section(row) if row.kind == :section

            place_task(row.task, table_rows.next, widths)
          end

          def place_section(row)
            middle = @body + (SECTION_ROW / 2)
            @rules << rule(@origin, middle, @origin + 5, middle)
            @texts << text(row.name, @origin + 10, middle + 4.157, TASK_FONT)
            @rules << section_tail(row, middle)
            @body += SECTION_ROW
          end

          def section_tail(row, middle)
            label_width = measure_text(row.name, font_size: TASK_FONT)[:width]
            rule(@origin + 15 + label_width, middle,
                 @origin + (@days * DAY) - 1, middle)
          end

          def rule(x_one, y_one, x_two, y_two)
            Sirena::Layout::Gantt::Line.new(x1: x_one, y1: y_one,
                                            x2: x_two, y2: y_two)
          end

          def place_task(task, cells, widths)
            place_cells(cells, widths)
            bar_y = @body + 2
            task[:milestone] ? diamond(task, bar_y) : bar(task, bar_y)
            @body += ROW
          end

          def place_cells(cells, widths)
            return if widths.empty?

            cells.each_with_index do |cell, index|
              @texts << text(cell, column_left(widths, index) + 5,
                             @body + 12.257, TABLE_FONT)
            end
          end

          def bar(task, bar_y)
            left = @origin + ((first_day(task) - 1) * DAY) + 2
            width = ((last_day(task) - first_day(task) + 1) * DAY) - 4
            @bars << Sirena::Layout::Gantt::Rect.new(
              x: left, y: bar_y, width: width, height: BAR, kind: "task",
            )
            caption(task, left, width, bar_y)
          end

          # The task's name sits inside its bar when it fits, after it when
          # it does not.
          def caption(task, left, width, bar_y)
            name = task[:description]
            fits = measure_text(name, font_size: TASK_FONT)[:width] + 8 <= width
            @texts << text(name, fits ? left + 4 : left + width + 4,
                           bar_y + 10.635, TASK_FONT)
          end

          def diamond(task, bar_y)
            centre = @origin + ((first_day(task) - 1) * DAY) + 2
            @diamonds << diamond_points(centre, bar_y + REACH)
            @texts << text(task[:description], centre + REACH + 4,
                           bar_y + 10.635, TASK_FONT)
          end

          def diamond_points(centre, middle)
            [[centre - REACH, middle], [centre, middle - REACH],
             [centre + REACH, middle], [centre, middle + REACH]]
              .map { |point| point.join(",") }.join(" ")
          end

          def finish(widths)
            bottom = @body
            width = @origin + (@days * DAY) + 21
            height = bottom + 16.36
            Scene.new(
              id: nil, width: width, height: height,
              view_box: "0 0 #{width.round(3)} #{height.round(3)}",
              grid_lines: grid_lines(widths, bottom), rules: @rules,
              bars: @bars, diamonds: @diamonds,
              texts: @texts + footer(bottom)
            )
          end

          def footer(bottom)
            day_labels(bottom + 12.668)
          end

          def grid_lines(widths, bottom)
            table_rules(bottom) + edge_rules(widths, bottom) + day_rules(bottom)
          end

          def table_rules(bottom)
            return [] if @origin.zero?

            [0.0, HEADER, bottom].map do |y_position|
              rule(0, y_position, @origin, y_position)
            end
          end

          def edge_rules(widths, bottom)
            return [] if widths.empty?

            edges = [0.0] + widths.each_index.map do |index|
              widths.first(index + 1).sum
            end
            edges.map { |x_position| rule(x_position, 0, x_position, bottom) }
          end

          def day_rules(bottom)
            (0..@days).map do |day|
              rule(@origin + (day * DAY), 6, @origin + (day * DAY), bottom + 8)
            end
          end
        end
      end
    end
  end
end
