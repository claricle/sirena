# frozen_string_literal: true

module Sirena
  module Notation
    # A registered plugin and the extensions it declared at registration.
    class Entry
      attr_reader :plugin, :extensions

      def initialize(plugin, extensions)
        @plugin = plugin
        @extensions = extensions
      end
    end
  end
end
