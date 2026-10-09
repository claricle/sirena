# frozen_string_literal: true

require_relative "../../../error"
require_relative "../../../error/diagram_type_error"
require_relative "../../../error/parse_error"
require_relative "../unsupported_construct_error"
require_relative "box"
require_relative "diagram"
require_relative "message"
require_relative "note"
require_relative "outline"
require_relative "participant"
require_relative "refusals"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Reads the PlantUML sequence subset: participant declarations,
        # messages, notes, `return`, dividers and alt/loop/group blocks. A
        # line outside it raises {UnsupportedConstructError}; never return a
        # diagram with a line skipped.
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

          COLOUR = /\#(\h{6}|\h{3}|red|green|blue|yellow|orange|purple|gray|
                       grey|cyan|magenta|lime|navy|teal|olive|maroon|silver|
                       aqua|fuchsia|pink|brown|black|white)(?!\w)/xi

          DECLARATION = /\A(#{KINDS.join('|')})[ \t]+(#{QUOTED}|#{NAME})
                         (?:[ \t]+as[ \t]+(#{NAME}))?\z/xio
          MESSAGE = /\A(#{QUOTED}|#{NAME})[ \t]*
                     (#{Regexp.union(ARROWS.keys.sort_by { |g| -g.length })})
                     [ \t]*(#{QUOTED}|#{NAME})[ \t]*
                     (--\+\+|\+\+--|\+\+|--|!!)?[ \t]*(#{COLOUR})?
                     [ \t]*(?::[ \t]*(.*))?\z/xo
          ACTIVATION = /\A(activate|deactivate)[ \t]+(#{QUOTED}|#{NAME})
                        (?:[ \t]+(#{COLOUR}))?\z/xio
          DESTROY = /\Adestroy[ \t]+(#{QUOTED}|#{NAME})\z/io
          MARKS = { "++" => [:on], "--" => [:off], "!!" => [:destroy],
                    "--++" => %i[off on], "++--" => %i[on off] }.freeze
          TARGET = /(?:#{QUOTED}|#{NAME})/
          NOTE = /\A(note|hnote|rnote)[ \t]+(left|right|over|across)
                  (?:[ \t]+of)?
                  (?:[ \t]+(#{TARGET}(?:[ \t]*,[ \t]*#{TARGET})*))?
                  (?:[ \t]+\#\w+)?[ \t]*(?::[ \t]*(.*))?\z/xio
          END_NOTE = /\Aend[ \t]*[hr]?note\z/i
          BLOCK = /\A(alt|opt|loop|par|critical|break|group)
                   (?:[ \t]+(?:\#\w+[ \t]*)?(.*))?\z/xi
          BRANCH = /\Aelse(?:[ \t]+(.*))?\z/i
          RETURN = /\Areturn(?:[ \t]+(.*))?\z/i
          DIVIDER = /\A==[ \t]*(.*?)[ \t]*==\z/
          BOX = /\Abox(?:[ \t]+(#{QUOTED}))?\z/io
          END_BOX = /\A(?:endbox|end[ \t]+box)\z/i
          PRAGMA = /\A!pragma[ \t]+(?:teoz|svginteractive)[ \t]+true\z/i
          STARTUML = /\A@startuml(?![A-Za-z0-9_])/
          LINE_END = /\r\n|\r|\n/

          TIMELINE = [[MESSAGE, :message], [NOTE, :note], [BLOCK, :block],
                      [BRANCH, :branch], [ACTIVATION, :activation],
                      [RETURN, :reply], [DIVIDER, :divider],
                      [DESTROY, :destroy]].freeze

          private_constant :TIMELINE, :NAME, :QUOTED, :KINDS, :ARROWS,
                           :DECLARATION, :MESSAGE, :BOX, :END_BOX, :STARTUML,
                           :LINE_END, :PRAGMA, :ACTIVATION, :MARKS, :TARGET,
                           :NOTE, :END_NOTE, :BLOCK, :BRANCH, :RETURN, :DIVIDER,
                           :DESTROY, :COLOUR

          # @param source [String] PlantUML source
          # @return [Diagram] the frozen diagram
          # @raise [UnsupportedConstructError] on the first line outside the
          #   subset
          # @raise [Sirena::Parser::ParseError] when the source is not valid
          #   UTF-8 or @enduml is missing
          def parse(source)
            @participants = {}
            @outline = Outline.new
            @boxes = []
            @open_box = nil
            @pending_note = nil
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
            return phase if skippable?(text)

            case phase
            when :before then before(text, number)
            when :statements then statement(text, number)
            else raise refusal(text, number, "content after @enduml")
            end
          end

          def skippable?(text)
            return false if @pending_note

            text.empty? || text.start_with?("'")
          end

          def before(text, number)
            return :statements if text == "@startuml"
            raise refusal(text, number, "diagram name") if STARTUML.match?(text)

            raise Sirena::Engine::DiagramTypeError,
                  "Unable to detect diagram type from source. " \
                  "Source must start with one of: @startuml"
          end

          def statement(text, number)
            return collect_note(text) if @pending_note
            return end_of_diagram(text, number) if text == "@enduml"
            return :statements if PRAGMA.match?(text)

            read(text, number)
            :statements
          end

          def read(text, number)
            if (match = DECLARATION.match(text))
              declare(match)
            elsif (match = BOX.match(text))
              open_box(match, text, number)
            else
              read_structure(text, number)
            end
          end

          def read_structure(text, number)
            if END_BOX.match?(text) && @open_box
              close_box
            elsif @open_box || !timeline(text)
              raise refusal(text, number)
            end
          end

          # Reads one line that belongs in the item sequence; false when it
          # is not one, or when it is out of place.
          def timeline(text)
            TIMELINE.each do |pattern, reader|
              match = pattern.match(text)
              return send(reader, match) if match
            end
            text.casecmp?("end") && @outline.close_block
          end

          def block(match)
            @outline.open_block(match[1].downcase, match[2].to_s.strip)
          end

          def branch(match)
            @outline.branch(match[1])
          end

          def reply(match)
            @outline.reply(match[1])
          end

          def activation(match)
            phase = match[1].casecmp?("activate") ? :on : :off
            return false if match[3] && phase == :off

            @outline.activation(phase, mention(match[2]), colour(match[4]))
          end

          def destroy(match)
            @outline.destroy(mention(match[1]))
          end

          def divider(match)
            @outline.divider(match[1])
          end

          def note(match)
            pending = pending_note_from(match)
            return false if hanging?(pending) && !@outline.after_message?

            @pending_note = pending
            match[4] ? collect_note(match[4].strip, inline: true) : true
          end

          def pending_note_from(match)
            { shape: match[1].downcase.to_sym, side: match[2].downcase.to_sym,
              targets: targets_of(match[3]), lines: [] }
          end

          def targets_of(list)
            list.to_s.split(",").map { |target| mention(target.strip) }
          end

          def hanging?(pending)
            pending[:targets].empty? && %i[left right].include?(pending[:side])
          end

          def collect_note(text, inline: false)
            if inline || END_NOTE.match?(text)
              finish_note(inline ? text : @pending_note[:lines].join("\n"))
            else
              @pending_note[:lines] << text
            end
            :statements
          end

          def finish_note(text)
            pending = @pending_note
            @pending_note = nil
            @outline.note(Note.new(shape: pending[:shape],
                                   side: pending[:side],
                                   targets: pending[:targets], text: text))
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
            raise unclosed_block if @outline.open_block?

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
            message = build_message(match)
            marks = marks(match[4], message, colour(match[6]))
            return false if match[5] && marks.none? { |phase,| phase == :on }

            @outline.message(message, marks)
          end

          def build_message(match)
            from, to = [match[1], match[3]].map { |name| mention(name) }
            arrow = ARROWS.fetch(match[2])
            from, to = to, from if arrow[:reversed]
            Message.new(from: from, to: to, label: match[7],
                        head: arrow[:head], dashed: arrow[:dashed])
          end

          # `--` deactivates the sender, `++` activates the receiver and `!!`
          # destroys it; a colour is the fill of the bar `++` opens.
          def marks(suffix, message, colour)
            MARKS.fetch(suffix, []).map do |phase|
              [phase, phase == :off ? message.from : message.to,
               phase == :on ? colour : nil]
            end
          end

          def colour(token)
            return unless token

            token.match?(/\A\h+\z/) ? "##{token}" : token.downcase
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
                        items: @outline.items.freeze, boxes: @boxes.freeze)
          end

          def unclosed_block
            Sirena::Parser::ParseError.new(
              "Parse error: a block is never closed with end",
            )
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
