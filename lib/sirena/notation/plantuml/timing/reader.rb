# frozen_string_literal: true

require "date"
require_relative "../state/reader"
require_relative "../unsupported_construct_error"
require_relative "model"

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Reads a timing diagram: participants, `@time` sections holding
        # state changes and messages, highlights and `scale`. A time is a
        # number, `+number` (after the previous `@`) or a `YYYY/MM/DD` date.
        # A line outside this subset raises {UnsupportedConstructError}.
        class Reader
          # A source line and its number.
          Line = Struct.new(:number, :text)

          ID = /[A-Za-z_]\w*/
          KINDS = "robust|concise|clock|binary|analog"
          TIME = %r{\+?\d+(?:\.\d+)?|\d{4}/\d{2}/\d{2}}
          CLOCK = /(?:[ \t]+with[ \t]+period[ \t]+(?<period>\d+)
                   (?:[ \t]+pulse[ \t]+(?<pulse>\d+))?
                   (?:[ \t]+offset[ \t]+(?<offset>\d+))?)?/x
          RULES = [
            [/\A(?<kind>#{KINDS})[ \t]+(?:"(?<title>[^"]+)"[ \t]+as[ \t]+
              (?<id>#{ID})|(?<bare>#{ID}))#{CLOCK}\z/xio, :participant],
            [/\A@(?<time>#{TIME})\z/o, :at],
            [/\A(?<id>#{ID})[ \t]+is[ \t]+(?<state>.+)\z/o, :change],
            [/\A(?<from>#{ID})[ \t]*->[ \t]*(?<to>#{ID})(?:@(?<arrives>\d+))?
              (?:[ \t]*:[ \t]*(?<label>.*))?\z/xo, :message],
            [/\Ahighlight[ \t]+(?<from>#{TIME})[ \t]+to[ \t]+(?<to>#{TIME})
              (?:[ \t]+(?<colour>\#\S+))?
              (?:[ \t]*:[ \t]*(?<caption>.*))?\z/xo, :highlight],
            [/\Ascale[ \t]+(?<units>\d+)[ \t]+as[ \t]+(?<pixels>\d+)[ \t]+
              pixels\z/xi, :scale],
          ].freeze
          SKIPPED = /\A(?:title|hide|skinparam|header|footer|caption)\b/i
          private_constant :Line, :ID, :KINDS, :TIME, :CLOCK, :RULES,
                           :SKIPPED

          # @param source [String] PlantUML source
          # @return [Diagram]
          # @raise [UnsupportedConstructError] on a line outside the subset
          def parse(source)
            @diagram = Diagram.new(participants: {}, changes: [],
                                   messages: [], highlights: [], dated: false)
            @now = 0
            State::Reader.lines_of(source).each do |text, number|
              read(Line.new(number, text))
            end
            @diagram
          end

          private

          def read(line)
            return if SKIPPED.match?(line.text)

            RULES.each do |pattern, handler|
              match = pattern.match(line.text)
              next unless match

              return send(handler, line,
                          match.named_captures.transform_keys(&:to_sym))
            end
            raise refused(line)
          end

          def refused(line)
            UnsupportedConstructError.new(construct: "timing statement",
                                          line: line.number, text: line.text)
          end

          def participant(line, fields)
            kind = fields[:kind].downcase
            raise refused(line) if kind == "clock" && fields[:period].to_i <= 0

            id = fields[:id] || fields[:bare]
            @diagram.participants[id] = Participant.new(
              id: id, title: fields[:title] || id, kind: kind, **clock(fields),
            )
          end

          def clock(fields)
            period = fields[:period].to_f
            { period: period, pulse: fields[:pulse]&.to_f || (period / 2),
              offset: fields[:offset].to_f }
          end

          def at(_line, fields)
            @now = moment(fields[:time], @now)
          end

          def change(line, fields)
            known(line, fields[:id])
            rest = fields[:state]
            fill, stroke = colours(rest[/\s+(#\S+)\z/, 1])
            @diagram.changes << Change.new(
              id: fields[:id], time: @now, state: state_name(rest),
              fill: fill, stroke: stroke
            )
          end

          def state_name(rest)
            rest.sub(/\s+#\S+\z/, "").strip.delete_prefix('"')
              .delete_suffix('"')
          end

          def message(line, fields)
            known(line, fields[:from])
            known(line, fields[:to])
            @diagram.messages << Message.new(
              from: fields[:from], to: fields[:to], time: @now,
              arrives: fields[:arrives]&.to_f, text: fields[:label].to_s
            )
          end

          def highlight(_line, fields)
            fill, stroke = colours(fields[:colour])
            @diagram.highlights << Highlight.new(
              from: moment(fields[:from], 0), to: moment(fields[:to], 0),
              fill: fill, stroke: stroke, caption: fields[:caption]&.strip
            )
          end

          def scale(_line, fields)
            @diagram.pixels_per_unit =
              fields[:pixels].to_f / fields[:units].to_i
          end

          def known(line, id)
            return if @diagram.participants.key?(id)

            raise refused(line)
          end

          # `#fill;line:colour` into [fill, line], each a CSS colour or nil.
          def colours(spec)
            return [nil, nil] unless spec

            fill, stroke = spec.delete_prefix("#").split(";line:", 2)
            [css(fill), css(stroke)]
          end

          def css(name)
            return if name.nil? || name.empty?
            return "##{name}" if name.match?(/\A\h{3}(?:\h{3})?\z/)

            name if name.match?(/\A[A-Za-z]+\z/)
          end

          def moment(text, base)
            return date_seconds(text) if text.include?("/")

            value = text.to_f
            text.start_with?("+") ? base + value : value
          end

          def date_seconds(text)
            @diagram.dated = true
            days = Date.strptime(text, "%Y/%m/%d") - Date.new(1970, 1, 1)
            days.to_i * 86_400.0
          rescue Date::Error
            raise refused(Line.new(0, text))
          end
        end
      end
    end
  end
end
