# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        class NewParser
          # The statements that open and close a branching construct. Each
          # keeps a frame on `@frames`; a frame remembers the branches
          # closed so far, and closing the construct joins them.
          module Blocks
            PATTERNS = [
              [/\A(?<kw>if|elseif)\s*\((?<cond>.*?)\)\s*
                (?:is\s*\((?<is>.*?)\)\s*)?
                then\s*(?:\((?<then>.*)\))?\z/xi, :on_if],
              [/\Aelse\s*(?:\((?<label>.*)\))?\z/i, :on_else],
              [/\Aend\s*if\z/i, :on_endif],
              [/\Awhile\s*\((?<cond>.*?)\)\s*(?:is\s*\((?<is>.*?)\))?\z/i,
               :on_while],
              [/\Aend\s*while\s*(?:\((?<label>.*)\))?\z/i, :on_endwhile],
              [/\Arepeat\z/i, :on_repeat],
              [/\Arepeat\s+while\s*\((?<cond>.*?)\)\s*
                (?:is\s*\((?<is>.*?)\)\s*)?
                (?:not\s*\((?<not>.*?)\))?\z/xi, :on_repeat_while],
              [/\Afork\z/i, :on_fork],
              [/\Afork\s+again\z/i, :on_fork_again],
              [/\Aend\s+(?<word>fork|merge)(?:\s*\{.*\})?\z/i, :on_end_fork],
              [/\Aswitch\s*\((?<cond>.*)\)\z/i, :on_switch],
              [/\Acase\s*\((?<label>.*)\)\z/i, :on_case],
              [/\Aend\s*switch\z/i, :on_endswitch],
            ].freeze

            private

            def on_if(match)
              label = label_text(match[:then] || match[:is])
              return elseif(match, label) unless match[:kw].casecmp?("if")

              decision = add(decision_node(match))
              @frames << { kind: "if", branches: [], decision: decision,
                           else: false }
              @ends = [[decision, label]]
            end

            def elseif(match, label)
              frame = top("if")
              frame[:branches].concat(@ends)
              decision = decision_node(match)
              @builder.connect(frame[:decision], decision)
              frame[:decision] = decision
              @ends = [[decision, label]]
            end

            def on_else(match)
              frame = top("if")
              frame[:branches].concat(@ends)
              frame[:else] = true
              @ends = [[frame[:decision], label_text(match[:label])]]
            end

            def on_endif(_match)
              frame = pop("if")
              branches = frame[:branches] + @ends
              branches << [frame[:decision], nil] unless frame[:else]
              join(branches, lane: frame[:decision].lane)
            end

            def on_while(match)
              decision = add(decision_node(match))
              @frames << { kind: "while", decision: decision }
              @ends = [[decision, label_text(match[:is])]]
            end

            def on_endwhile(match)
              decision = pop("while")[:decision]
              @ends.each do |from, label|
                @builder.connect(from, decision, label: label)
              end
              @ends = [[decision, label_text(match[:label])]]
            end

            def on_repeat(_match)
              @frames << { kind: "repeat", start: add(@builder.node(:merge)) }
            end

            def on_repeat_while(match)
              start = pop("repeat")[:start]
              decision = add(decision_node(match))
              @builder.connect(decision, start, label: label_text(match[:is]))
              @ends = [[decision, label_text(match[:not])]]
            end

            def on_fork(_match)
              head = add(@builder.node(:bar))
              @frames << { kind: "fork", branches: [], head: head }
            end

            def on_fork_again(_match)
              frame = top("fork")
              frame[:branches].concat(@ends)
              @ends = [[frame[:head], nil]]
            end

            def on_end_fork(match)
              frame = pop("fork")
              kind = match[:word].casecmp?("merge") ? :merge : :bar
              join(frame[:branches] + @ends, kind: kind)
            end

            def on_switch(match)
              decision = add(decision_node(match))
              @frames << { kind: "switch", decision: decision, branches: [] }
              @ends = []
            end

            def on_case(match)
              frame = top("switch")
              frame[:branches].concat(@ends)
              @ends = [[frame[:decision], label_text(match[:label])]]
            end

            def on_endswitch(_match)
              frame = pop("switch")
              join(frame[:branches] + @ends, lane: frame[:decision].lane)
            end

            def decision_node(match)
              @builder.node(:decision, text: clean(match[:cond]))
            end

            # Closes a branching construct: many open ends become one
            # merge node, one stays as it is, none means the flow ended. The
            # diamond stays in the swimlane of the decision it closes, as
            # PlantUML draws it, whichever lane the branches ended in.
            def join(branches, kind: :merge, lane: nil)
              return @ends = branches if branches.size < 2

              merge = @builder.node(kind)
              merge.lane = lane if lane
              branches.each do |from, label|
                @builder.connect(from, merge, label: label)
              end
              @ends = [[merge, nil]]
            end

            def label_text(text)
              text.nil? || text.strip.empty? ? nil : clean(text)
            end

            def top(kind)
              frame = @frames.last
              return frame if frame && frame[:kind] == kind

              refuse("#{@line.split.first} outside #{kind}", @line)
            end

            def pop(kind)
              top(kind)
              @frames.pop
            end
          end
        end
      end
    end
  end
end
