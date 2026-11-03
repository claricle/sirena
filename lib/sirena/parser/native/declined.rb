# frozen_string_literal: true

module Sirena
  module Parser
    module Native
      # Raised by a native builder for input where the Ruby builder's
      # answer is the reference (for example the "[]" Parslet leaves for
      # an empty accessibility text). The caller runs the Ruby path.
      class Declined < StandardError; end
    end
  end
end
