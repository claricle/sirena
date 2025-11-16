# frozen_string_literal: true

require_relative '../../diagram/info'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Info diagram model.
      #
      # Converts the parse tree output from Grammars::Info into a
      # fully-formed Diagram::Info object.
      class Info
        # Transform parse tree into Info diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Info] the info diagram model
        def apply(tree)
          diagram = Diagram::Info.new

          # Process tree structure
          if tree.is_a?(Array)
            tree.each do |item|
              next unless item.is_a?(Hash)

              process_show_info_inline(diagram, item) if item.key?(:show_info_inline)
              process_show_info_body(diagram, item) if item.key?(:show_info_body)
            end
          elsif tree.is_a?(Hash)
            process_show_info_inline(diagram, tree) if tree.key?(:show_info_inline)
            process_show_info_body(diagram, tree) if tree.key?(:show_info_body)
          end

          diagram
        end

        private

        def process_show_info_inline(diagram, item)
          show_info = item[:show_info_inline]
          return unless show_info
          return if show_info.to_s.strip.empty?

          # showInfo flag is present inline
          diagram.show_info = true
        end

        def process_show_info_body(diagram, item)
          show_info = item[:show_info_body]
          return unless show_info
          return if show_info.to_s.strip.empty?

          # showInfo flag is present in body
          diagram.show_info = true
        end
      end
    end
  end
end