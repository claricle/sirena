# frozen_string_literal: true

require_relative "../../diagram/er_diagram"

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
          "||" => "one",
          "o{" => "zero_or_more",
          "|{" => "one_or_more",
          "}o" => "zero_or_one",
          "{o" => "zero_or_more",
          "{|" => "one_or_more",
          "}{" => "one_or_more",
          "{}" => "one_or_more",
          "o|" => "zero_or_one",
          "|o" => "zero_or_one",
          "}|" => "one_or_more",
        }.freeze

        KEY_TYPES = %w[PK FK UK].freeze

        STATEMENT_HANDLERS = {
          classdef: :process_class_def,
          entity: :process_entity_definition,
          relationship: :process_relationship,
        }.freeze
        private_constant :STATEMENT_HANDLERS

        # Transform parse tree into ER diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::ErDiagram] the ER diagram model
        def apply(tree)
          diagram = Diagram::ErDiagram.new
          statements(tree).each do |statement|
            process_statement(diagram, statement)
          end

          diagram
        end

        private

        def statements(tree)
          if tree.is_a?(Array)
            return tree.grep(Hash).reject { |item| item[:header] }
          end
          if tree.is_a?(Hash) && tree[:statements]
            return Array(tree[:statements]).grep(Hash)
          end

          []
        end

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_statement(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          kind = statement_kind(stmt)
          send(STATEMENT_HANDLERS.fetch(kind), diagram, stmt) if kind
        end

        def statement_kind(stmt)
          return :classdef if stmt[:classdef_names]
          return :entity if stmt[:entity_id]

          :relationship if stmt[:from_id] && stmt[:to_id] && stmt[:pattern]
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
          entity_id = unquote(stmt[:entity_id])
          entity = find_or_create_entity(diagram, entity_id)

          add_entity_classes(entity, stmt[:entity_classes])
          add_attributes(entity, stmt[:attributes])
        end

        def add_attributes(entity, captures)
          Array(captures).grep(Hash).each do |capture|
            entity.attributes << build_attribute(capture)
          end
        end

        def build_attribute(capture)
          attribute = Diagram::ErAttribute.new
          attribute.name = capture[:name].to_s
          assign_attribute_details(attribute, capture)
          attribute
        end

        def assign_attribute_details(attribute, capture)
          if capture[:type]
            attribute.attribute_type = extract_attribute_type(capture[:type])
          end
          attribute.key_type = extract_key_type(capture[:key]) if capture[:key]
          attribute.note = extract_text(capture[:note]) if capture[:note]
        end

        def process_relationship(diagram, stmt)
          from_id = unquote(stmt[:from_id])
          to_id = unquote(stmt[:to_id])
          ensure_relationship_entities(diagram, stmt, from_id, to_id)
          diagram.relationships << build_relationship(stmt, from_id, to_id)
        end

        def ensure_relationship_entities(diagram, stmt, from_id, to_id)
          from = ensure_entity(diagram, from_id)
          to = ensure_entity(diagram, to_id)
          add_entity_classes(from, stmt[:from_classes])
          add_entity_classes(to, stmt[:to_classes])
        end

        def build_relationship(stmt, from_id, to_id)
          cardinality_from, cardinality_to, relationship_type =
            relationship_pattern(stmt[:pattern])
          Diagram::ErRelationship.new.tap do |relationship|
            relationship.from_id = from_id
            relationship.to_id = to_id
            relationship.relationship_type = relationship_type
            relationship.cardinality_from = cardinality_from
            relationship.cardinality_to = cardinality_to
            relationship.label = relationship_label(stmt)
          end
        end

        def relationship_pattern(pattern)
          from = CARDINALITY_SYMBOLS[extract_text(pattern[:card_from])]
          to = CARDINALITY_SYMBOLS[extract_text(pattern[:card_to])]
          operator = extract_text(pattern[:operator])
          type = operator == "==" ? "identifying" : "non-identifying"
          [from, to, type]
        end

        def relationship_label(stmt)
          label = stmt.dig(:label, :label_text)
          return unless label

          text = extract_text(label).strip
          text unless text.empty?
        end

        def unquote(slice)
          slice.to_s.delete_prefix('"').delete_suffix('"')
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
          slice.to_s.split(",").map(&:strip)
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
            current, index = next_tilde_set(sets, index, output)
            output << process_tilde_set(current)
          end
          output.join
        end

        def next_tilde_set(sets, index, output)
          current = sets[index]
          return [current, index + 1] unless combinable_tilde_set?(sets, index)

          output.pop
          ["#{sets[index - 1]},#{sets[index + 1]}", index + 2]
        end

        def combinable_tilde_set?(sets, index)
          sets[index] == "," && index.positive? && index + 1 < sets.length &&
            should_combine_tilde_sets?(sets[index - 1], sets[index + 1])
        end

        # A comma inside a generic's tildes (`Map~K, V~`) splits the input
        # into three parts by the split above; rejoin them when both the
        # part before and the part after the comma carry exactly one
        # tilde each, meaning they are the two halves of one pair mermaid
        # split apart, not two independent tilde types.
        def should_combine_tilde_sets?(previous_set, next_set)
          previous_set.count("~") == 1 && next_set.count("~") == 1
        end

        # One pass collects every tilde's index rather than rescanning the
        # entire array after each replacement. Pairing outside-in from that
        # fixed list gives the same result: first with last, then second with
        # second-to-last, and so on.
        def process_tilde_set(input)
          has_starting_tilde = input.count("~").odd? && input.start_with?("~")
          input = input[1..] if has_starting_tilde
          chars = input.chars
          replace_tilde_pairs(chars)
          chars.unshift("~") if has_starting_tilde
          chars.join
        end

        def replace_tilde_pairs(chars)
          indices = chars.each_index.select { |index| chars[index] == "~" }
          (indices.length / 2).times do |pair|
            chars[indices[pair]] = "<"
            chars[indices[-(pair + 1)]] = ">"
          end
        end

        def extract_text(value)
          case value
          when Hash
            extract_hash_text(value)
          when String
            value
          else
            value.to_s
          end
        end

        # Both grammar rules that capture `:string` (`tilde_type`, `note`)
        # go through `GreedyRun`/`DelimitedRun`, whose zero-length match is a
        # real empty `Parslet::Slice`, not `[]`; `.to_s` is safe for `~~` and
        # `""` alike.
        def extract_hash_text(value)
          return value[:string].to_s if value.key?(:string)
          return value[:key_type].to_s if value[:key_type]

          value.values.first.to_s
        end

        # Several keys join into one comma-separated string, "PK,FK",
        # which is also how mermaid prints them.
        def extract_key_type(value)
          keys = [value].flatten.map { |key| extract_text(key) }
          keys = keys.select { |key| KEY_TYPES.include?(key) }
          keys.join(",") unless keys.empty?
        end
      end
    end
  end
end
