# frozen_string_literal: true

require_relative "base"
require_relative "grammars/treemap"
require_relative "builders/treemap"
require_relative "../diagram/treemap"

module Sirena
  module Parser
    # Parser for treemap diagrams using Parslet
    class Treemap < Base
      grammar Grammars::Treemap
      builder Builders::Treemap

      private

      # The builder's Parslet pass returns statement data, not a diagram.
      def create_diagram(data)
        self.class.builder.new.build_diagram(data)
      end
    end
  end
end
