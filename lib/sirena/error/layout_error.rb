# frozen_string_literal: true

require_relative '../error'

module Sirena
  module Layout
    # Error raised during layout. A Sirena::Error so Engine#render
    # can let it propagate unwrapped instead of collapsing it into
    # PipelineError.
    class LayoutError < Sirena::Error; end
  end
end
