# frozen_string_literal: true

module Sirena
  module Layout
    # The "<<person>>" caption Mermaid draws above a C4 element's name.
    class C4Stereotype
      EXTERNAL_SUFFIX = "_Ext"

      # @param element_type [String, nil] e.g. "Person_Ext", "SystemDb"
      # @return [String, nil] e.g. "<<external_person>>"
      def self.text(element_type)
        return if element_type.nil? || element_type.empty?

        prefix = element_type.end_with?(EXTERNAL_SUFFIX) ? "external_" : ""
        base = element_type.delete_suffix(EXTERNAL_SUFFIX)
        snake = base.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        "<<#{prefix}#{snake}>>"
      end

      # @param element_type [String, nil] e.g. "SystemDb_Ext", "ContainerQueue"
      # @return [String, nil] "database", "queue", or nil for a plain box
      def self.shape(element_type)
        base = element_type.to_s.delete_suffix(EXTERNAL_SUFFIX)
        return "database" if base.end_with?("Db")

        "queue" if base.end_with?("Queue")
      end
    end
  end
end
