# frozen_string_literal: true

require_relative '../error'

module Sirena
  module Transform
    # Error raised during transformation. A Sirena::Error so Engine#render
    # can let it propagate unwrapped instead of collapsing it into
    # PipelineError. Named Transform for now; LAYERS.md renames this stage
    # to Layout once item 03 lands.
    class TransformError < Sirena::Error; end
  end
end
