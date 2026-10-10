# frozen_string_literal: true

require_relative "greedy_run"

module Sirena
  module Parser
    module Atoms
      # Matches a run of `broad_class` (Kleene star, via `GreedyRun` --
      # exact across chunk boundaries because a pure character-class-star
      # is position-independent), then un-consumes trailing characters
      # matching `trim_class`, giving them back to the source.
      #
      # This reproduces a backreference-free version of Ruby/JS's own
      # backtracking for `\w([-.\/\w]*[-\w])?`: matching the whole greedy
      # run and then trimming trailing non-`trim_class` characters off
      # the end is equivalent to backtracking the greedy run one
      # character at a time until the required trailing char matches.
      class TrimmedRun < Parslet::Atoms::Base
        def initialize(broad_class, trim_class)
          super()
          @run = GreedyRun.new(broad_class, min: 0)
          @trim_re = /(?:#{trim_class})*\z/
        end

        def try(source, context, _consume_all)
          # `@run` is `GreedyRun.new(broad_class, min: 0)` -- a Kleene star
          # matches zero or more, so it can never fail; there is no
          # failure branch to handle here.
          result = @run.apply(source, context, false).last
          kept, trimmed = trim_match(result.to_s)
          source.bytepos -= trimmed.bytesize
          succ(Parslet::Slice.new(result.position, kept, result.line_cache))
        end

        def trim_match(matched)
          trimmed = matched[@trim_re]
          kept = matched[0...(matched.length - trimmed.length)]
          [kept, trimmed]
        end

        def to_s_inner(_prec)
          "#{@run.inspect}(trim: #{@trim_re.inspect})"
        end
      end
    end
  end
end
