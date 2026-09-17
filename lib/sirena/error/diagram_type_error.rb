# frozen_string_literal: true

require_relative '../error'

module Sirena
  class Engine
    # Error raised when diagram type cannot be detected
    class DiagramTypeError < Sirena::Error; end
  end
end
