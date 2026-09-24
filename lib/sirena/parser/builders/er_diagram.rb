# frozen_string_literal: true

require_relative '../../diagram/er_diagram'

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to ER diagram model.
      #
      # Converts the parse tree output from Grammars::ErDiagram into a
      # fully-formed Diagram::ErDiagram object with entities, attributes,
      # and relationships.
      class ErDiagram
        # Cardinality symbol mappings
        CARDINALITY_SYMBOLS = {
          '||' => 'one',
          'o{' => 'zero_or_more',
          '|{' => 'one_or_more',
          '}o' => 'zero_or_one',
          '{o' => 'zero_or_more',
          '{|' => 'one_or_more',
          '}{' => 'one_or_more',
          '{}' => 'one_or_more',
          'o|' => 'zero_or_one',
          '|o' => 'zero_or_one',
          '}|' => 'one_or_more'
        }.freeze

        # Transform parse tree into ER diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::ErDiagram] the ER diagram model
        def apply(tree)
          diagram = Diagram::ErDiagram.new

          # Tree is an array: [header, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              next if item.is_a?(Hash) && item[:header] # Skip header
              process_statement(diagram, item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash) && tree[:statements]
            process_statements(diagram, tree[:statements])
          end

          diagram
        end

        private

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_statement(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:classdef_names]
            # Style class declaration
            process_class_def(diagram, stmt)
          elsif stmt[:entity_id]
            # Entity, with or without an attribute block
            process_entity_definition(diagram, stmt)
          elsif stmt[:from_id] && stmt[:to_id] && stmt[:pattern]
            # Relationship
            process_relationship(diagram, stmt)
          end
        end

        def process_class_def(diagram, stmt)
          styles = stmt[:classdef_styles].to_s
          split_class_names(stmt[:classdef_names]).each do |name|
            diagram.add_class_def(name, styles)
          end
        end

        # Handles both `CAR { ... }` and a bare `CAR`. An empty block yields
        # a nil `:attributes`, so routing on `:entity_id` alone is what keeps
        # `CAR:::x {}` from losing its classes. A5 pins that.
        def process_entity_definition(diagram, stmt)
          entity_id = stmt[:entity_id].to_s
          entity = find_or_create_entity(diagram, entity_id)

          add_entity_classes(entity, stmt[:entity_classes])

          # Process attributes
          if stmt[:attributes]
            attributes = Array(stmt[:attributes])
            attributes.each do |attr_data|
              next unless attr_data.is_a?(Hash)

              attribute = Diagram::ErAttribute.new.tap do |attr|
                attr.name = attr_data[:name].to_s
                attr.attribute_type = extract_attribute_type(attr_data[:type]) if attr_data[:type]
                attr.key_type = extract_key_type(attr_data[:key]) if attr_data[:key]
                attr.note = extract_text(attr_data[:note]) if attr_data[:note]
              end

              entity.attributes << attribute
            end
          end
        end

        def process_relationship(diagram, stmt)
          from_id = stmt[:from_id].to_s
          to_id = stmt[:to_id].to_s
          pattern = stmt[:pattern]

          # Ensure entities exist
          add_entity_classes(ensure_entity(diagram, from_id),
                             stmt[:from_classes])
          add_entity_classes(ensure_entity(diagram, to_id),
                             stmt[:to_classes])

          # Parse relationship pattern
          card_from = extract_text(pattern[:card_from])
          card_to = extract_text(pattern[:card_to])
          operator = extract_text(pattern[:operator])

          # Map cardinalities
          card_from_val = CARDINALITY_SYMBOLS[card_from]
          card_to_val = CARDINALITY_SYMBOLS[card_to]

          # Determine relationship type from operator
          rel_type = operator == '==' ? 'identifying' : 'non-identifying'

          # Extract label if present
          label = nil
          if stmt[:label] && stmt[:label][:label_text]
            label = extract_text(stmt[:label][:label_text]).strip
          end

          relationship = Diagram::ErRelationship.new.tap do |rel|
            rel.from_id = from_id
            rel.to_id = to_id
            rel.relationship_type = rel_type
            rel.cardinality_from = card_from_val
            rel.cardinality_to = card_to_val
            rel.label = label unless label.nil? || label.empty?
          end

          diagram.relationships << relationship
        end

        def find_or_create_entity(diagram, entity_id)
          existing = diagram.find_entity(entity_id)
          return existing if existing

          entity = Diagram::ErEntity.new.tap do |e|
            e.id = entity_id
            e.name = entity_id
          end
          diagram.entities << entity
          entity
        end

        def ensure_entity(diagram, entity_id)
          find_or_create_entity(diagram, entity_id)
        end

        # Appends rather than replaces, so `CAR:::a,b` and `CAR:::a` on one
        # line plus `CAR:::b` on the next reach the same state. NOT deduped:
        # verified against mermaid's own db that a repeated assignment stays
        # in `cssClasses` (`"default a b a"` for `CAR:::a,b` then `CAR:::a`),
        # so the resolved style IS order-sensitive — a repeat moves that
        # class to the end and lets it win a later conflict. Deduping here
        # was wrong; see the renderer's entity_styles for where the order is
        # applied.
        def add_entity_classes(entity, slice)
          return if slice.nil?

          entity.classes.concat(split_class_names(slice))
        end

        def split_class_names(slice)
          slice.to_s.split(',').map(&:strip)
        end

        # `tilde_type` in the grammar captures the FULL match -- optional
        # non-whitespace prefix/suffix plus both tildes -- so mermaid's
        # `foo~bar baz~qux` keeps its inner tilde untouched. Mermaid does
        # NOT strip the tildes on display: it renders `~T~` as `<T>` (see
        # `spec/mermaid/unknown/079_platform_yari2_78.svg`, which shows
        # `&lt;timestamp with time zone&gt;`). `parse_generic_types` below
        # ports mermaid's own function of the same name
        # (`packages/mermaid/src/diagrams/common/common.ts`), which is
        # what the renderer actually calls on an attribute's type text.
        def extract_attribute_type(value)
          parse_generic_types(extract_text(value))
        end

        # Pairs tildes from the outside in and turns each pair into a
        # `<`/`>`, e.g. `~T~` -> `<T>`, `~Map~K, V~~` -> `<Map<K, V>>`.
        # A leading tilde with no partner (an odd count that starts with
        # `~`) carries no display meaning and passes through unchanged --
        # `~test` stays `~test`, only `~test~T~` becomes `~test<T>`.
        def parse_generic_types(input)
          sets = input.split(/(,)/)
          output = []
          index = 0
          while index < sets.length
            this_set = sets[index]
            if this_set == ',' && index.positive? && index + 1 < sets.length &&
               should_combine_tilde_sets?(sets[index - 1], sets[index + 1])
              this_set = "#{sets[index - 1]},#{sets[index + 1]}"
              index += 1
              output.pop
            end
            output << process_tilde_set(this_set)
            index += 1
          end
          output.join
        end

        # A comma inside a generic's tildes (`Map~K, V~`) splits the input
        # into three parts by the split above; rejoin them when both the
        # part before and the part after the comma carry exactly one
        # tilde each, meaning they are the two halves of one pair mermaid
        # split apart, not two independent tilde types.
        def should_combine_tilde_sets?(previous_set, next_set)
          previous_set.count('~') == 1 && next_set.count('~') == 1
        end

        def process_tilde_set(input)
          # Fast path: the vast majority of attribute types carry no tilde at
          # all, so skip the char-array allocation below for them -- the
          # loop already produces this same result for 0 or 1 tildes.
          return input if input.count('~') <= 1

          has_starting_tilde = input.count('~').odd? && input.start_with?('~')
          input = input[1..] if has_starting_tilde

          chars = input.chars
          # One pass to collect every tilde's index, instead of the
          # `index`/`rindex` pair rescanning the WHOLE array after every
          # replacement (O(n) per pair, O(n^2) total on an n-tilde input).
          # Pairing outside-in from a fixed index list gives the same
          # result in one scan: pair 0 is (first, last), pair 1 is
          # (second, second-to-last), and so on.
          tilde_indices = chars.each_index.select { |i| chars[i] == '~' }
          tilde_indices.length.fdiv(2).floor.times do |pair|
            first = tilde_indices[pair]
            last = tilde_indices[-(pair + 1)]
            break if first == last

            chars[first] = '<'
            chars[last] = '>'
          end

          chars.unshift('~') if has_starting_tilde
          chars.join
        end

        def extract_text(value)
          case value
          when Hash
            if value.key?(:string)
              # A zero-length `.repeat.as(:string)` capture (the empty
              # `~~` type, or an empty `""` note) comes back from Parslet
              # as `[]`, not an empty Parslet::Slice -- `[].to_s` would
              # otherwise ship the literal text "[]" into the model.
              value[:string].is_a?(Array) ? '' : value[:string].to_s
            elsif value[:key_type]
              value[:key_type].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end
        end

        def extract_key_type(value)
          text = extract_text(value)
          text if %w[PK FK UK].include?(text)
        end
      end
    end
  end
end