# frozen_string_literal: true

require_relative "../../../error"
require_relative "../../../error/diagram_type_error"
require_relative "../../../error/parse_error"
require_relative "../unsupported_construct_error"
require_relative "box"
require_relative "diagram"
require_relative "message"
require_relative "participant"
require_relative "refusals"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Reads the PlantUML sequence subset: participant declarations and
        # plain messages. A line outside it raises {UnsupportedConstructError};
        # never return a diagram with a line skipped.
        class Parser
          NAME = /[A-Za-z_][A-Za-z0-9_]*/
          QUOTED = /"[^"\n]+"/
          KINDS = %w[participant actor boundary control entity database
                     collections queue].freeze
          ARROWS = {
            "->" => { head: :filled, dashed: false, reversed: false },
            "->>" => { head: :open, dashed: false, reversed: false },
            "-->" => { head: :filled, dashed: true, reversed: false },
            "-->>" => { head: :open, dashed: true, reversed: false },
            "<-" => { head: :filled, dashed: false, reversed: true },
            "<<-" => { head: :open, dashed: false, reversed: true },
            "<--" => { head: :filled, dashed: true, reversed: true },
            "<<--" => { head: :open, dashed: true, reversed: true },
          }.freeze

          DECLARATION = /\A(#{KINDS.join('|')})[ \t]+(#{QUOTED}|#{NAME})
                         (?:[ \t]+as[ \t]+(#{NAME}))?\z/xio
          MESSAGE = /\A(#{QUOTED}|#{NAME})[ \t]*
                     (#{Regexp.union(ARROWS.keys.sort_by { |g| -g.length })})
                     [ \t]*(#{QUOTED}|#{NAME})[ \t]*(?::[ \t]*(.*))?\z/xo
          BOX = /\Abox(?:[ \t]+(#{QUOTED}))?\z/io
          END_BOX = /\A(?:endbox|end[ \t]+box)\z/i
          STARTUML = /\A@startuml(?![A-Za-z0-9_])/
          LINE_END = /\r\n|\r|\n/

          private_constant :NAME, :QUOTED, :KINDS, :ARROWS, :DECLARATION,
                           :MESSAGE, :BOX, :END_BOX, :STARTUML, :LINE_END

          # @param source [String] PlantUML source
          # @return [Diagram] the frozen diagram
          # @raise [UnsupportedConstructError] on the first line outside the
          #   subset
          # @raise [Sirena::Parser::ParseError] when the source is not valid
          #   UTF-8 or @enduml is missing
          def parse(source)
            @participants = {}
            @messages = []
            @boxes = []
            @open_box = nil
            phase = :before
            lines_of(source).each_with_index do |line, index|
              phase = step(phase, line.strip, index + 1)
            end
            finish(phase)
          end

          private

          def lines_of(source)
            text = source.dup.force_encoding(Encoding::UTF_8)
            unless text.valid_encoding?
              raise Sirena::Parser::ParseError,
                    "Parse error: source is not valid UTF-8"
            end

            text.delete_prefix("﻿").split(LINE_END)
          end

          def step(phase, text, number)
            return phase if text.empty? || text.start_with?("'")

            case phase
            when :before then before(text, number)
            when :statements then statement(text, number)
            else raise refusal(text, number, "content after @enduml")
            end
          end

          def before(text, number)
            return :statements if text == "@startuml"
            raise refusal(text, number, "diagram name") if STARTUML.match?(text)

            raise Sirena::Engine::DiagramTypeError,
                  "Unable to detect diagram type from source. " \
                  "Source must start with one of: @startuml"
          end

          def statement(text, number)
            return end_of_diagram(text, number) if text == "@enduml"

            read(text, number)
            :statements
          end

          def read(text, number)
            if (match = DECLARATION.match(text))
              declare(match)
            elsif (match = BOX.match(text))
              open_box(match, text, number)
            elsif END_BOX.match?(text) && @open_box
              close_box
            elsif (match = MESSAGE.match(text)) && !@open_box
              message(match)
            else
              raise refusal(text, number)
            end
          end

          def open_box(match, text, number)
            raise refusal(text, number, "nested box") if @open_box

            @open_box = { title: unquote(match[1].to_s), members: [] }
          end

          def close_box
            @boxes << Box.new(**@open_box)
            @open_box = nil
          end

          def end_of_diagram(text, number)
            raise refusal(text, number, "empty diagram") if @participants.empty?
            raise unclosed_box if @open_box

            :after
          end

          def declare(match)
            display = unquote(match[2])
            id = match[3] || display
            @participants[id] ||= Participant.new(
              id: id, label: display, kind: match[1].downcase.to_sym,
            )
            @open_box[:members] << id if @open_box
          end

          def message(match)
            from, to = [match[1], match[3]].map { |name| mention(name) }
            arrow = ARROWS.fetch(match[2])
            from, to = to, from if arrow[:reversed]
            @messages << Message.new(from: from, to: to, label: match[4],
                                     head: arrow[:head],
                                     dashed: arrow[:dashed])
          end

          def mention(name)
            id = unquote(name)
            @participants[id] ||= Participant.new(id: id)
            id
          end

          def unquote(name)
            name.delete_prefix('"').delete_suffix('"')
          end

          def finish(phase)
            if phase == :before
              raise Sirena::Engine::DiagramTypeError,
                    "Unable to detect diagram type from source. " \
                    "Source must start with one of: @startuml"
            end
            return diagram if phase == :after

            raise Sirena::Parser::ParseError,
                  "Parse error: missing @enduml before the end of the source"
          end

          def diagram
            check_boxes
            Diagram.new(participants: @participants.values.freeze,
                        messages: @messages.freeze, boxes: @boxes.freeze)
          end

          def unclosed_box
            Sirena::Parser::ParseError.new(
              "Parse error: box #{@open_box[:title].inspect} is never " \
              "closed with endbox",
            )
          end

          def check_boxes
            ids = @participants.keys
            @boxes.each do |box|
              places = box.members.map { |id| ids.index(id) }.sort
              next if places.each_cons(2).all? { |a, b| b == a + 1 }

              raise Sirena::Parser::ParseError,
                    "Parse error: participants of box #{box.title.inspect} " \
                    "are not neighbours, which is not supported"
            end
          end

          def refusal(text, number, construct = nil)
            UnsupportedConstructError.new(
              construct: construct || Refusals.name_for(text),
              line: number, text: text
            )
          end
        end
      end
    end
  end
end
