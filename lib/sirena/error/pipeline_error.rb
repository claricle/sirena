# frozen_string_literal: true

require_relative '../error'

module Sirena
  class Engine
    # Error raised during pipeline execution
    class PipelineError < Sirena::Error; end
  end
end
