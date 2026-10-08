# frozen_string_literal: true

require_relative "../error"

module Sirena
  # Raised by {Sirena::Notation.register} when a plugin breaks the notation
  # contract: a malformed member, a duplicate id, or an extension another
  # notation already claims.
  class NotationRegistrationError < Sirena::Error; end
end
