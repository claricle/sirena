# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/gantt"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Gantt from the native parse tree of the +gantt+
        # entry. The statement semantics are the Parslet builder's own; only
        # the tree shape differs: the native task details are the field
        # list itself, without Parslet's +:parts+ wrapper.
        class Gantt < Parser::Builders::Gantt
          # @param tree [Hash, Array, Parsanol::Slice] native parse tree
          # @return [Diagram::Gantt]
          def apply(tree)
            Diagram::Gantt.new.tap do |diagram|
              @current_section = nil
              @click_map = {}
              Text.items(tree).each { |item| process_item(diagram, item) }
              apply_click_handlers(diagram)
            end
          end

          private

          def process_task_details(task, details)
            super(task, { parts: details })
          end
        end
      end
    end
  end
end
