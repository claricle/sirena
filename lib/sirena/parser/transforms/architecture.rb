# frozen_string_literal: true

require_relative '../../diagram/architecture'

module Sirena
  module Parser
    module Transforms
      # Transform for architecture diagrams
      class Architecture
        def apply(tree)
          diagram = Diagram::ArchitectureDiagram.new

          # Process tree
          if tree.is_a?(Array)
            tree.each do |item|
              process_statement(diagram, item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash)
            process_statement(diagram, tree)
          end

          diagram
        end

        private

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:header]
            # Skip header marker
            nil
          elsif stmt[:title]
            diagram.title = extract_text(stmt[:title])
          elsif stmt[:acc_title]
            diagram.acc_title = extract_text(stmt[:acc_title])
          elsif stmt[:acc_descr]
            diagram.acc_descr = extract_text(stmt[:acc_descr])
          elsif stmt[:from] && stmt[:to]
            # Edge: has from and to
            diagram.edges << create_edge(stmt)
          elsif stmt[:stmt_type]
            # Check statement type to distinguish group from service
            if extract_text(stmt[:stmt_type]) == 'group'
              diagram.groups << create_group(stmt)
            elsif extract_text(stmt[:stmt_type]) == 'service'
              diagram.services << create_service(stmt)
            end
          end
        end

        def create_group(data)
          group = Diagram::ArchitectureDiagram::Group.new
          group.id = extract_text(data[:id]) if data[:id]
          group.label = extract_text(data[:label]) if data[:label]
          group.icon = extract_text(data[:icon]) if data[:icon]
          group.parent_id = extract_text(data[:parent]) if data[:parent] && !data[:parent].to_s.empty?
          group
        end

        def create_service(data)
          service = Diagram::ArchitectureDiagram::Service.new
          service.id = extract_text(data[:id]) if data[:id]
          service.label = extract_text(data[:label]) if data[:label]
          service.icon = extract_text(data[:icon]) if data[:icon]
          service.group_id = extract_text(data[:group]) if data[:group] && !data[:group].to_s.empty?
          service
        end

        def create_edge(data)
          edge = Diagram::ArchitectureDiagram::Edge.new
          edge.from_id = extract_text(data[:from]) if data[:from]
          edge.to_id = extract_text(data[:to]) if data[:to]
          edge.from_position = extract_text(data[:from_pos]) if data[:from_pos]
          edge.to_position = extract_text(data[:to_pos]) if data[:to_pos]
          edge.label = extract_text(data[:label]) if data[:label]
          edge
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end.strip
        end
      end
    end
  end
end