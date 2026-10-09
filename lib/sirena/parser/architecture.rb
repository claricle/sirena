# frozen_string_literal: true

require_relative "base"
require_relative "grammars/architecture"
require_relative "builders/architecture"

module Sirena
  module Parser
    # Parser for architecture diagrams
    class Architecture < Base
      grammar Grammars::Architecture
      builder Builders::Architecture

      # Stripped before parsing. The grammar tolerates leading and trailing
      # whitespace, but String#strip also removes ,  and , which the
      # grammar does not, so dropping it changes which inputs parse. Error
      # positions are therefore relative to the stripped source.
      def parse(input)
        super(input.strip)
      end
    end
  end
end
