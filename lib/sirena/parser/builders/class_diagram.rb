# frozen_string_literal: true

require_relative "capture_string"
require_relative "../../diagram/class_diagram"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to Class diagram model.
      #
      # Converts the parse tree output from Grammars::ClassDiagram into a
      # fully-formed Diagram::ClassDiagram object with entities and
      # relationships.
      class ClassDiagram
        include CaptureString

        # Relationship type mappings from operators
        RELATIONSHIP_TYPES = {
          "<|--" => "inheritance",
          "--|>" => "inheritance",
          "*--" => "composition",
          "--*" => "composition",
          "o--" => "aggregation",
          "--o" => "aggregation",
          "-->" => "association",
          "<--" => "association",
          "--" => "association",
          "..|>" => "realization",
          "<|.." => "realization",
          "..>" => "dependency",
          "<.." => "dependency",
          ".." => "association",
        }.freeze

        # Operators where arrow points left (reverse direction)
        LEFT_POINTING = ["<|--", "<--", "<|..", "<.."].freeze

        # `id1` keeps its parsed position for both ends here (mmdc never
        # swaps for these forms, unlike LEFT_POINTING's single-sided ones),
        # so `start_marker`/`end_marker` land on from_id/to_id as parsed.
        # `nil` means no marker is drawn at that end.
        #
        # `o..` carries a marker on one side only and has no structural
        # two-way counterpart, so it stays a literal lookup. Every genuine
        # two-way combination (both ends carrying a marker, e.g. `<--*`,
        # `o--|>`, `<|--|>`) is decomposed structurally by
        # #mixed_markers_for instead -- add a new combination there, not
        # as a hardcoded entry here.
        MIXED_MARKER_ENDPOINTS = {
          "o.." => {
            start_marker: "aggregation", end_marker: nil, dashed: true
          },
        }.freeze

        # Marker glyph -> the marker type it draws, verified against
        # mermaid-cli 11.12.0's bundled classDiagram.jison parser
        # (`getArrowMarker(type)` per glyph): `<`/`>` decompose to
        # DEPENDENCY, so `<--*`'s `<` is a dependency marker, not absent.
        MARKER_TYPES = {
          "<|" => "inheritance",
          "|>" => "inheritance",
          "*" => "composition",
          "o" => "aggregation",
          "<" => "dependency",
          ">" => "dependency",
        }.freeze

        # Longest markers first so `<|`/`|>` win over the `<`/`>` they
        # would otherwise be read as a prefix of.
        SORTED_MARKER_GLYPHS = Regexp.union(
          MARKER_TYPES.keys.sort_by { |marker| -marker.length },
        )

        # Matches a two-way operator into its left marker, link style, and
        # right marker -- the same [Relation Type][Link][Relation Type]
        # structure Parser::Grammars::ClassDiagram::MIXED_OPERATOR_STRINGS
        # generates from.
        MIXED_OPERATOR_PATTERN = /
          \A(?<left>#{SORTED_MARKER_GLYPHS})
          (?<link>--|\.\.)
          (?<right>#{SORTED_MARKER_GLYPHS})\z
        /x

        # `name(params) rest`: mmdc reads the LAST `(...)` in the text as the
        # parameter list, so `foo()bar()` is method `foo()bar`, not `foo`
        # with a stray `)bar(` as its params.
        RAW_METHOD = /\A(?<name>.*)\((?<params>[^)]*)\)(?<rest>.*)\z/

        # Visibility symbol mappings
        VISIBILITY_SYMBOLS = {
          "+" => "public",
          "-" => "private",
          "#" => "protected",
          "~" => "package",
        }.freeze

        STATEMENT_HANDLERS = [
          %i[namespace_statement? process_namespace],
          %i[class_declaration? process_class_declaration],
          %i[standalone_stereotype? process_standalone_stereotype],
          %i[colon_member? process_colon_member],
          %i[relationship? process_relationship],
          %i[direction_statement? process_direction],
          %i[ignored_statement? ignore_statement],
          %i[standalone_class? process_standalone_class],
        ].freeze
        private_constant :STATEMENT_HANDLERS

        # Transform parse tree into Class diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @param source [String] the text the tree was parsed from
        # @return [Diagram::ClassDiagram] the Class diagram model
        def apply(tree, source)
          @source = source
          @diagram = Diagram::ClassDiagram.new
          # Which statement created each class: mmdc keeps only the generic
          # written on the mention that creates it.
          @statement_count = 0
          @created_in = {}
          process_tree(tree)
          @diagram
        end

        private

        # Tree is an array: [header, direction, ...statements]
        def process_tree(tree)
          return tree.each { |item| process_item(item) } if tree.is_a?(Array)

          process_item(tree) if tree.is_a?(Hash)
        end

        def process_item(item)
          # Process header to get direction
          if item[:direction] && item[:direction][:dir_value]
            @diagram.direction = extract_text(item[:direction][:dir_value])
          end

          # Process statements
          process_statement(item) unless item[:header] || item[:direction]
        end

        def process_statement(stmt)
          @statement_count += 1
          handler = STATEMENT_HANDLERS.find do |predicate, _action|
            send(predicate, stmt)
          end
          send(handler.last, stmt) if handler
        end

        def namespace_statement?(stmt)
          stmt[:namespace_keyword]
        end

        def class_declaration?(stmt)
          stmt[:keyword] == "class" && stmt[:class_id]
        end

        def standalone_stereotype?(stmt)
          stmt[:stereotype] && stmt[:class_id] && !stmt[:keyword]
        end

        def colon_member?(stmt)
          stmt[:class_id] &&
            (stmt[:member] || stmt[:raw_member] || stmt[:body_stereotype])
        end

        def relationship?(stmt)
          stmt[:from_id] && stmt[:to_id] && stmt[:operator]
        end

        def direction_statement?(stmt)
          stmt[:direction_keyword]
        end

        def ignored_statement?(stmt)
          stmt[:link_keyword] || stmt[:callback_keyword] || stmt[:ignored]
        end

        def standalone_class?(stmt)
          stmt[:class_id] && !stmt[:keyword]
        end

        def process_direction(stmt)
          @diagram.direction = extract_text(stmt[:dir_value])
        end

        # Link, callback, click, styling, accessibility text and notes parse
        # but carry nothing the model keeps (yet).
        def ignore_statement(_stmt); end

        def process_standalone_class(stmt)
          entity = ensure_entity_exists(class_id_text(stmt[:class_id]))
          apply_generic(entity, stmt[:generic])
        end

        # Namespace members keep their plain, global ids; the parser's
        # ClassNamespaces records which box each one belongs to.
        def process_namespace(stmt)
          Array(stmt[:namespace_body]).each { |s| process_statement(s) }
        end

        def process_class_declaration(stmt)
          class_id = class_id_text(stmt[:class_id])
          entity = find_or_create_entity(class_id)
          label = declaration_label(stmt)
          apply_declaration_stereotype(entity, stmt)
          apply_generic(entity, stmt[:generic]) unless label
          entity.name = label if label
          process_class_body(entity, stmt[:body]) if stmt[:body]
        end

        # An empty explicit label falls back to the class id.
        def declaration_label(stmt)
          return unless stmt[:text_label].is_a?(Hash)

          label = extract_text(stmt[:text_label][:string])
          label unless label.empty?
        end

        def apply_declaration_stereotype(entity, stmt)
          stereotype = stmt.dig(:stereotype, :stereotype_value)
          entity.stereotype ||= extract_text(stereotype) if stereotype
        end

        def process_standalone_stereotype(stmt)
          class_id = class_id_text(stmt[:class_id])

          entity = find_or_create_entity(class_id)

          entity.stereotype ||=
            extract_text(stmt[:stereotype][:stereotype_value])
        end

        def process_colon_member(stmt)
          class_id = class_id_text(stmt[:class_id])

          entity = find_or_create_entity(class_id)
          apply_generic(entity, stmt[:generic])

          add_member(entity, stmt)
        end

        def process_class_body(entity, body_data)
          return unless body_data.is_a?(Array)

          body_data.each do |member_item|
            add_member(entity, member_item)
          end
        end

        # mmdc keeps the first annotation a class gets, wherever it is written.
        def add_member(entity, item)
          if item[:body_stereotype]
            entity.stereotype ||= extract_text(item[:body_stereotype])
          elsif item[:raw_member]
            add_raw_member(entity, extract_text(item[:raw_member]))
          else
            add_structured_member(entity, item)
          end
        end

        def add_structured_member(entity, item)
          visibility = parse_visibility(item[:visibility])
          member = item[:member]
          source_text = member_source(item.slice(:visibility, :member))
          if member[:method_name]
            add_method_to_entity(entity, member, visibility, source_text)
          else
            add_attribute_to_entity(entity, member, visibility, source_text)
          end
        end

        # The member as written, read back from the slices the grammar
        # captured: from the first to the end of the last.
        def member_source(item)
          slices = []
          collect_slices(item, slices)
          first = slices.min_by(&:offset)
          last = slices.max_by { |slice| slice.offset + slice.size }
          @source[first.offset...(last.offset + last.size)]
        end

        def collect_slices(node, slices)
          case node
          when Hash then node.each_value { |v| collect_slices(v, slices) }
          when Parslet::Slice then slices << node
          end
        end

        # Text the structured member rules did not read. mmdc calls it a
        # method when it holds a `)` and refuses a `)` outside the shape
        # `name(...) type`. The `*` and `$` marks it allows after an
        # attribute or method have no place in the model and are dropped.
        def add_raw_member(entity, text)
          source_text = text.strip
          visibility, text = split_visibility(source_text)
          member = parse_raw_member(text, visibility, source_text)
          raw_member_collection(entity, member) << member
        end

        def parse_raw_member(text, visibility, source_text)
          call = text.match(RAW_METHOD)
          return raw_method(call, visibility, source_text) if
            call && !call[:name].strip.empty?

          unreadable_member!(text) if text.include?(")")
          raw_attribute(text, visibility, source_text)
        end

        def raw_member_collection(entity, member)
          return entity.class_methods if member.is_a?(Diagram::ClassMethod)

          entity.attributes
        end

        def unreadable_member!(text)
          raise Parser::ParseError,
                "Cannot read #{text.inspect} as a class member."
        end

        def raw_attribute(text, visibility, source_text)
          Diagram::ClassAttribute.new(
            name: text.sub(/\s*[*$]\z/, ""),
            visibility: visibility,
            text: source_text,
          )
        end

        # A leading mark names the visibility; the rest is the member.
        def split_visibility(text)
          visible = text.match(/\A(?<symbol>[-+#~])\s*(?<rest>\S.*)\z/m)
          return ["public", text] unless visible

          [VISIBILITY_SYMBOLS.fetch(visible[:symbol]), visible[:rest]]
        end

        # The `*` (abstract) and `$` (static) mmdc allows after a method have
        # no place in the model and are dropped. The mark only reads as a
        # classifier when it touches the closing `)` directly; a space
        # before it (`foo() $bar`) means `$bar` is the return type text, not
        # a marked-then-typed method.
        def raw_method(call, visibility, source_text)
          return_type = call[:rest].sub(/\A[*$]?\s*/, "").sub(/\s*[*$]\z/, "")
          Diagram::ClassMethod.new(
            name: call[:name].strip, parameters: call[:params],
            return_type: return_type.empty? ? nil : return_type,
            visibility: visibility, text: source_text
          )
        end

        def add_method_to_entity(entity, method_data, visibility, source_text)
          entity.class_methods << Diagram::ClassMethod.new(
            name: extract_text(method_data[:method_name]),
            parameters: method_parameters(method_data),
            return_type: method_return_type(method_data),
            visibility: visibility,
            text: source_text,
          )
        end

        def method_parameters(method_data)
          return "" unless method_data[:parameters]

          extract_text(method_data[:parameters])
        end

        def method_return_type(method_data)
          type = method_data.dig(:return_type, :type)
          extract_text(type) if type
        end

        def add_attribute_to_entity(entity, attr_data, visibility, source_text)
          attr_type = attr_data[:type] ? extract_text(attr_data[:type]) : nil

          entity.attributes << Diagram::ClassAttribute.new(
            name: extract_text(attr_data[:attr_name]), type: attr_type,
            visibility: visibility, text: source_text
          )
        end

        def process_relationship(stmt)
          ids = relationship_ids(stmt)
          operator = relationship_operator(stmt)
          ensure_relationship_entities(ids, stmt)
          append_relationship(stmt, operator, ids)
        end

        def relationship_ids(stmt)
          [class_id_text(stmt[:from_id]), class_id_text(stmt[:to_id])]
        end

        def relationship_operator(stmt)
          extract_text(stmt[:operator][:arrow])
        end

        def ensure_relationship_entities(ids, stmt)
          apply_generic(ensure_entity_exists(ids[0]), stmt[:from_generic])
          apply_generic(ensure_entity_exists(ids[1]), stmt[:to_generic])
        end

        def append_relationship(stmt, operator, ids)
          cards = relationship_cardinalities(stmt)
          ends = relationship_ends(*ids, operator, *cards)
          @diagram.relationships << build_relationship(stmt, operator, ends)
        end

        def relationship_cardinalities(stmt)
          %i[source_card target_card].map do |key|
            extract_text(stmt[key][:string]) if stmt[key]
          end
        end

        def relationship_ends(
          from_id, to_id, operator, source_card, target_card
        )
          return [from_id, to_id, source_card, target_card] unless
            LEFT_POINTING.include?(operator)

          [to_id, from_id, target_card, source_card]
        end

        def relationship_label(stmt)
          pipe_label = stmt.dig(:pipe_label, :label_text)
          return extract_text(pipe_label).gsub(/^["']|["']$/, "") if pipe_label

          colon_label = stmt.dig(:colon_label, :label_text)
          extract_text(colon_label).strip if colon_label
        end

        def build_relationship(stmt, operator, ends)
          relationship = Diagram::ClassRelationship.new(
            **relationship_attributes(stmt, operator, ends),
          )
          apply_mixed_markers(relationship, operator)
          relationship
        end

        def relationship_attributes(stmt, operator, ends)
          from_id, to_id, source_card, target_card = ends
          {
            from_id: from_id, to_id: to_id,
            relationship_type: RELATIONSHIP_TYPES.fetch(
              operator, "association"
            ),
            label: relationship_label(stmt),
            source_cardinality: source_card,
            target_cardinality: target_card
          }
        end

        def apply_mixed_markers(relationship, operator)
          markers = mixed_markers_for(operator)
          return unless markers

          relationship.start_marker = markers[:start_marker]
          relationship.end_marker = markers[:end_marker]
          relationship.dashed = markers[:dashed]
        end

        # Looks up an `o..`-style single-marker operator by literal string,
        # or decomposes a genuine two-way operator (a marker on both ends)
        # structurally via MARKER_TYPES. `nil` for every single-sided
        # operator, which keeps its existing RELATIONSHIP_TYPES rendering.
        def mixed_markers_for(operator)
          return MIXED_MARKER_ENDPOINTS[operator] if
            MIXED_MARKER_ENDPOINTS.key?(operator)

          match = MIXED_OPERATOR_PATTERN.match(operator)
          return nil unless match

          {
            start_marker: MARKER_TYPES.fetch(match[:left]),
            end_marker: MARKER_TYPES.fetch(match[:right]),
            dashed: match[:link] == "..",
          }
        end

        def find_or_create_entity(class_id)
          existing = @diagram.find_entity(class_id)
          return existing if existing

          entity = Diagram::ClassEntity.new.tap do |e|
            e.id = class_id
            e.name = class_id
          end
          @diagram.entities << entity
          @created_in[class_id] = @statement_count
          entity
        end

        def ensure_entity_exists(class_id)
          find_or_create_entity(class_id)
        end

        # The name of a class reference. Backticks only quote the name:
        # `Car` and Car are one class.
        def class_id_text(node)
          extract_text(node).sub(/\A`(.*)`\z/m, '\1')
        end

        # Shows a generic on the display name ("Car~T~"), unless a text label
        # already names the class: mmdc renders `class Animal~T~["A label"]`
        # as "A label". Only the statement that creates the class counts, as
        # in mmdc: `A --> B` then `A~T~ --> C` leaves A without a generic, and
        # `A~T~ --> B` then `A~U~ --> C` keeps T.
        def apply_generic(entity, generic)
          creating = @created_in.delete(entity.id) == @statement_count
          return unless creating && generic.is_a?(Hash) &&
            generic[:generic_type]

          generic_type = extract_text(generic[:generic_type])
          entity.name = "#{entity.name}~#{generic_type}~"
        end

        def parse_visibility(vis_data)
          return "public" unless vis_data

          symbol = extract_text(vis_data[:vis_symbol])
          VISIBILITY_SYMBOLS[symbol] || "public"
        end

        # Every capture reaching here is a Slice (or the `[]` of an empty
        # repeat); no rule nests another name inside the one it passes.
        def extract_text(value)
          capture_string(value)
        end
      end
    end
  end
end
