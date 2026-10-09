# frozen_string_literal: true

require_relative "../error"

module Sirena
  module Parser
    # A value the source spelled validly but the diagram type does not
    # allow, such as a user journey score outside 1..5. Not a ParseError:
    # the source parsed.
    class ScoreError < Sirena::Error; end
  end
end
