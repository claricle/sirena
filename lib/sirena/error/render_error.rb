# frozen_string_literal: true

require_relative '../error'

module Sirena
  module Renderer
    # Error raised during rendering. A Sirena::Error so Engine#render can
    # let it propagate unwrapped instead of collapsing it into
    # PipelineError.
    class RenderError < Sirena::Error; end
  end
end
