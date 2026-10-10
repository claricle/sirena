# frozen_string_literal: true

require_relative "../../../error"
require_relative "../../../error/diagram_type_error"
require_relative "../../../error/parse_error"
require_relative "../unsupported_construct_error"
require_relative "arrow_syntax"
require_relative "box"
require_relative "diagram"
require_relative "edge"
require_relative "message"
require_relative "note"
require_relative "outline"
require_relative "parallel_message"
require_relative "participant"
require_relative "ref"
require_relative "refusals"
require_relative "style"

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

          COLOUR = /\#(\h{6}|\h{3}|red|green|blue|yellow|orange|purple|gray|
                       grey|cyan|magenta|lime|navy|teal|olive|maroon|silver|
                       aqua|fuchsia|pink|brown|black|white)(?!\w)/xi

          DECLARATION = /\A(#{KINDS.join('|')})[ \t]+(#{QUOTED}|#{NAME})
                         (?:[ \t]+as[ \t]+(#{NAME}))?
                         (?:[ \t]+<<[ \t]*([^<>\n]+?)[ \t]*>>)?\z/xio
          SKINPARAM_WIDTH = /\Askinparam[ \t]+MinClassWidth[ \t]+(\d+)\z/i
          HIDE_FOOTBOX = /\Ahide[ \t]+footbox\z/i
          STYLE_OPEN = /\A<style>\z/i
          STYLE_CLOSE = /\A<\/style>\z/i
          MESSAGE = /\A(#{QUOTED}|#{NAME}|[\[?](?=[-<\\\/oxOX]))[ \t]*
                     (#{ArrowSyntax::SOURCE})
                     [ \t]*(#{QUOTED}|#{NAME}|(?<![ \t])[\]?])[ \t]*
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
          REF = /\Aref[ \t]+over[ \t]+(#{TARGET}(?:[ \t]*,[ \t]*#{TARGET})*)
                 [ \t]*:[ \t]*(\S.*)\z/xio
          END_NOTE = /\Aend[ \t]*[hr]?note\z/i
          BLOCK = /\A(alt|opt|loop|par|critical|break|group)
                   (?:[ \t]+(?:\#\w+[ \t]*)?(.*))?\z/xi
          BRANCH = /\Aelse(?:[ \t]+(.*))?\z/i
          RETURN = /\Areturn(?:[ \t]+(.*))?\z/i
          DIVIDER = /\A==[ \t]*(.*?)[ \t]*==\z/
          BOX = /\Abox(?:[ \t]+(#{QUOTED}))?\z/io
          END_BOX = /\A(?:endbox|end[ \t]+box)\z/i
          PRAGMA = /\A!pragma[ \t]+(teoz|svginteractive)[ \t]+true\z/i
          STARTUML = /\A@startuml(?![A-Za-z0-9_])/
          LINE_END = /\r\n|\r|\n/
          PARALLEL = /\A&[ \t]*(.*)\z/

          PARALLEL_KINDS = [MESSAGE, NOTE, BLOCK].freeze
          TIMELINE = [[MESSAGE, :message], [NOTE, :note], [BLOCK, :block],
                      [REF, :ref], [BRANCH, :branch], [ACTIVATION, :activation],
                      [RETURN, :reply], [DIVIDER, :divider],
                      [DESTROY, :destroy]].freeze

          private_constant :TIMELINE, :NAME, :QUOTED, :KINDS,
                           :DECLARATION, :MESSAGE, :BOX, :END_BOX, :STARTUML,
                           :LINE_END, :PRAGMA, :ACTIVATION, :MARKS, :TARGET,
                           :NOTE, :END_NOTE, :REF, :BLOCK, :BRANCH, :RETURN,
                           :DIVIDER, :DESTROY, :COLOUR, :SKINPARAM_WIDTH,
                           :STYLE_OPEN, :STYLE_CLOSE, :PARALLEL,
                           :PARALLEL_KINDS, :HIDE_FOOTBOX

          # @param source [String] PlantUML source
          # @return [Diagram] the frozen diagram
          # @raise [UnsupportedConstructError] on the first line outside the
          #   subset
          # @raise [Sirena::Parser::ParseError] when the source is not valid
          #   UTF-8 or @enduml is missing
          def parse(source)
            start_empty
            phase = :before
            lines_of(source).each_with_index do |line, index|
              phase = step(phase, line.strip, index + 1)
            end
            finish(phase)
          end

          private

          def start_empty
            @participants = {}
            @outline = Outline.new
            @boxes = []
            @open_boxes = []
            @pending_note = nil
            @pending_style = nil
            @min_head_width = nil
            @teoz = false
            @parallel = false
            @footbox = true
          end

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
            return collect_style(text) if @pending_style
            return end_of_diagram(text, number) if text == "@enduml"
            return pragma(PRAGMA.match(text)) if PRAGMA.match?(text)

            read(text, number)
            :statements
          end

          def pragma(match)
            @teoz ||= match[1].casecmp?("teoz")
            :statements
          end

          def read(text, number)
            if (match = DECLARATION.match(text)) && plain_stereotype?(match)
              declare(match)
            elsif (match = BOX.match(text))
              open_box(match)
            else
              read_setting(text, number)
            end
          end

          def read_setting(text, number)
            if (match = SKINPARAM_WIDTH.match(text))
              @min_head_width = match[1].to_i
            elsif HIDE_FOOTBOX.match?(text)
              @footbox = false
            elsif STYLE_OPEN.match?(text)
              @pending_style = { line: number, text: text, lines: [] }
            else
              read_structure(text, number)
            end
          end

          # A stereotype is drawn above the label, where the other kinds
          # already draw their name.
          def plain_stereotype?(match)
            match[4].nil? || match[1].casecmp?("participant")
          end

          def collect_style(text)
            if STYLE_CLOSE.match?(text)
              close_style
            else
              @pending_style[:lines] << text
            end
            :statements
          end

          def close_style
            style = @pending_style
            @pending_style = nil
            width = Style.minimum_width(style[:lines].join("\n"))
            raise refusal(style[:text], style[:line]) unless width

            @min_head_width = width
          end

          def read_structure(text, number)
            if END_BOX.match?(text) && @open_boxes.any?
              close_box
            elsif @open_boxes.any? || !timeline(text)
              raise refusal(text, number)
            end
          end

          # Reads one line that belongs in the item sequence; false when it
          # is not one, or when it is out of place.
          def timeline(text)
            parallel = PARALLEL.match(text)
            return parallel_line(parallel[1]) if parallel

            read_timeline(text)
          end

          # Only teoz draws `&` on the row above; without it PlantUML
          # stacks the line as an ordinary one, so it stays refused.
          def parallel_line(text)
            return false unless @teoz && @outline.anchored?
            return false unless PARALLEL_KINDS.any? { |kind| kind.match?(text) }

            @parallel = true
            read_timeline(text)
          ensure
            @parallel = false
          end

          def read_timeline(text)
            TIMELINE.each do |pattern, reader|
              match = pattern.match(text)
              return send(reader, match) if match
            end
            text.casecmp?("end") && @outline.close_block
          end

          def block(match)
            @outline.open_block(match[1].downcase, match[2].to_s.strip,
                                parallel: @parallel)
          end

          # A label with a line break is the multi-line form; not drawn.
          def ref(match)
            return false if match[2].include?("\\n")

            @outline.ref(Ref.new(targets: targets_of(match[1]),
                                 label: match[2].strip))
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
            return false if hanging?(pending) && !hangs_from_something?

            @pending_note = pending
            match[4] ? collect_note(match[4].strip, inline: true) : true
          end

          def hangs_from_something?
            @outline.after_message? || @outline.after_block?
          end

          def pending_note_from(match)
            { shape: match[1].downcase.to_sym, side: match[2].downcase.to_sym,
              targets: targets_of(match[3]), lines: [], parallel: @parallel }
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
                                   targets: pending[:targets], text: text,
                                   parallel: pending[:parallel]))
          end

          # PlantUML does not draw a box inside a box: the inner one is drawn
          # beside the outer one's own members, and an outer box with none is
          # not drawn at all.
          def open_box(match)
            @open_boxes.last&.store(:nested, true)
            @open_boxes << { title: unquote(match[1].to_s), members: [] }
          end

          def close_box
            box = @open_boxes.pop
            return if box[:nested] && box[:members].empty?

            @boxes << Box.new(title: box[:title], members: box[:members])
          end

          def end_of_diagram(text, number)
            raise refusal(text, number, "empty diagram") if @participants.empty?
            raise unclosed_box if @open_boxes.any?
            raise unclosed_block if @outline.open_block?

            :after
          end

          def declare(match)
            display = unquote(match[2])
            id = match[3] || display
            @participants[id] ||= Participant.new(
              id: id, label: display, kind: match[1].downcase.to_sym,
              stereotype: match[4]
            )
            @open_boxes.last[:members] << id if @open_boxes.any?
          end

          def message(match)
            message = build_message(match) or return false
            return false if unplaceable?(message, match[4])

            marks = marks(match[4], message, colour(match[6]))
            return false if match[5] && marks.none? { |phase,| phase == :on }

            @outline.message(message, marks)
          end

          def build_message(match)
            style, reversed = ArrowSyntax.read(match[2])
            ends = [endpoint(match[1], :left), endpoint(match[3], :right)]
            return unless style && edges_readable?(ends, reversed)

            from, to = reversed ? ends.reverse : ends
            kind = @parallel ? ParallelMessage : Message
            kind.new(from: from, to: to, label: match[7], style: style)
          end

          def endpoint(token, side)
            Edge.read(token, side) || mention(token)
          end

          # At most one end is missing, and a diagram-wide edge only for the
          # forms measured against PlantUML: written `[->` or `->]`.
          def edges_readable?(ends, reversed)
            edges = ends.grep(Edge)
            edges.size < 2 && edges.none? { |edge| reversed && edge.global? }
          end

          # A `?` end has no ring in the slice, and a missing end cannot be
          # activated or destroyed.
          def unplaceable?(message, suffix)
            edge = message.edge or return false

            !suffix.nil? || (edge.local? && message.edge_end.circle)
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
                        items: @outline.items.freeze, boxes: @boxes.freeze,
                        min_head_width: @min_head_width, footbox: @footbox)
          end

          def unclosed_block
            Sirena::Parser::ParseError.new(
              "Parse error: a block is never closed with end",
            )
          end

          def unclosed_box
            Sirena::Parser::ParseError.new(
              "Parse error: box #{@open_boxes.last[:title].inspect} is never " \
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
