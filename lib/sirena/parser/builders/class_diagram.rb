# frozen_string_literal: true

require_relative '../../diagram/class_diagram'

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to Class diagram model.
      #
      # Converts the parse tree output from Grammars::ClassDiagram into a
      # fully-formed Diagram::ClassDiagram object with entities and
      # relationships.
      class ClassDiagram
        # Relationship type mappings from operators
        RELATIONSHIP_TYPES = {
          '<|--' => 'inheritance',
          '--|>' => 'inheritance',
          '*--' => 'composition',
          '--*' => 'composition',
          'o--' => 'aggregation',
          '--o' => 'aggregation',
          '-->' => 'association',
          '<--' => 'association',
          '--' => 'association',
          '..|>' => 'realization',
          '<|..' => 'realization',
          '..>' => 'dependency',
          '<..' => 'dependency',
          '..' => 'association'
        }.freeze

        # Operators where arrow points left (reverse direction)
        LEFT_POINTING = ['<|--', '<--', '<|..', '<..'].freeze

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
          'o..' => { start_marker: 'aggregation', end_marker: nil, dashed: true }
        }.freeze

        # Marker glyph -> the marker type it draws, verified against
        # mermaid-cli 11.12.0's bundled classDiagram.jison parser
        # (`getArrowMarker(type)` per glyph): `<`/`>` decompose to
        # DEPENDENCY, so `<--*`'s `<` is a dependency marker, not absent.
        MARKER_TYPES = {
          '<|' => 'inheritance',
          '|>' => 'inheritance',
          '*' => 'composition',
          'o' => 'aggregation',
          '<' => 'dependency',
          '>' => 'dependency'
        }.freeze

        # Matches a two-way operator into its left marker, link style, and
        # right marker -- the same [Relation Type][Link][Relation Type]
        # structure Parser::Grammars::ClassDiagram::MIXED_OPERATOR_STRINGS
        # generates from. Longest markers first so `<|`/`|>` win over the
        # `<`/`>` they would otherwise be read as a prefix of.
        MIXED_OPERATOR_PATTERN = /
          \A(?<left>#{Regexp.union(MARKER_TYPES.keys.sort_by { |m| -m.length })})
          (?<link>--|\.\.)
          (?<right>#{Regexp.union(MARKER_TYPES.keys.sort_by { |m| -m.length })})\z
        /x

        # `name(params) rest`: mmdc reads the LAST `(...)` in the text as the
        # parameter list, so `foo()bar()` is method `foo()bar`, not `foo`
        # with a stray `)bar(` as its params.
        RAW_METHOD = /\A(?<name>.*)\((?<params>[^)]*)\)(?<rest>.*)\z/

        # Visibility symbol mappings
        VISIBILITY_SYMBOLS = {
          '+' => 'public',
          '-' => 'private',
          '#' => 'protected',
          '~' => 'package'
        }.freeze

        # Transform parse tree into Class diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::ClassDiagram] the Class diagram model
        def apply(tree)
          @diagram = Diagram::ClassDiagram.new
          # Classes given an explicit label, so a later generic on the same id
          # does not append to it.
          @labelled_ids = []
          # Which statement created each class: mmdc keeps only the generic
          # written on the mention that creates it.
          @statement_count = 0
          @created_in = {}
          @current_namespace = nil

          # Tree is an array: [header, direction, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              process_item(item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash)
            process_item(tree)
          end

          @diagram
        end

        private

        def process_item(item)
          return unless item.is_a?(Hash)

          # Process header to get direction
          if item[:direction] && item[:direction][:dir_value]
            @diagram.direction = extract_text(item[:direction][:dir_value])
          end

          # Process statements
          process_statement(item) unless item[:header] || item[:direction]
        end

        def process_statement(stmt)
          return unless stmt.is_a?(Hash)

          @statement_count += 1
          if stmt[:namespace_keyword]
            # Namespace block
            process_namespace(stmt)
          elsif stmt[:keyword] == 'class' && stmt[:class_id]
            # Class declaration
            process_class_declaration(stmt)
          elsif stmt[:stereotype] && stmt[:class_id] && !stmt[:keyword]
            # Standalone stereotype
            process_standalone_stereotype(stmt)
          elsif stmt[:class_id] && (stmt[:member] || stmt[:raw_member] || stmt[:body_stereotype])
            # Colon member definition
            process_colon_member(stmt)
          elsif stmt[:from_id] && stmt[:to_id] && stmt[:operator]
            # Relationship
            process_relationship(stmt)
          elsif stmt[:direction_keyword]
            @diagram.direction = extract_text(stmt[:dir_value])
          elsif stmt[:link_keyword] || stmt[:callback_keyword] || stmt[:ignored]
            # Link, callback, click, styling, accessibility text and notes
            # parse but carry nothing the model keeps (yet).
            nil
          elsif stmt[:class_id] && !stmt[:keyword]
            # Standalone class
            entity = ensure_entity_exists(qualify_name(class_id_text(stmt[:class_id])))
            apply_generic(entity, stmt[:generic])
          end
        end

        def process_namespace(stmt)
          namespace_name = extract_text(stmt[:namespace_name])
          old_namespace = @current_namespace
          @current_namespace = namespace_name

          # Process namespace body
          if stmt[:namespace_body]
            statements = Array(stmt[:namespace_body])
            statements.each do |s|
              process_statement(s) if s.is_a?(Hash)
            end
          end

          @current_namespace = old_namespace
        end

        def process_class_declaration(stmt)
          class_id = qualify_name(class_id_text(stmt[:class_id]))

          entity = find_or_create_entity(class_id)

          # `class C1[]` is an empty label and must fall back to the id, so an
          # empty string counts as absent here.
          label = extract_text(stmt[:text_label][:string]) if stmt[:text_label].is_a?(Hash)
          label = nil if label.nil? || label.empty?

          # Handle stereotype
          if stmt[:stereotype] && stmt[:stereotype][:stereotype_value]
            entity.stereotype ||= extract_text(stmt[:stereotype][:stereotype_value])
          end

          # Handle generic parameters.
          #
          # Appended to the name for display, but only when there is no
          # explicit label. mermaid renders `class Animal~T~["A label"]` as
          # "A label", not "A label~T~", so a label wins outright.
          # Skipped when a label is present on THIS declaration, and also when
          # an earlier declaration already labelled this class — otherwise
          # `class C1["Label"]` followed by `class C1~T~` produced `Label~T~`
          # where mmdc renders `Label`.
          apply_generic(entity, stmt[:generic]) unless label

          # An explicit text label replaces the display name. The id is
          # untouched, which is what keeps relationships resolving — and the
          # assignment is unconditional on purpose, because
          # find_or_create_entity may have already set name to the id when a
          # relationship mentioned this class first.
          if label
            entity.name = label
            @labelled_ids << entity.id
          end

          # Handle class body
          process_class_body(entity, stmt[:body]) if stmt[:body]
        end

        def process_standalone_stereotype(stmt)
          class_id = qualify_name(class_id_text(stmt[:class_id]))

          entity = find_or_create_entity(class_id)

          if stmt[:stereotype][:stereotype_value]
            entity.stereotype ||= extract_text(stmt[:stereotype][:stereotype_value])
          end
        end

        def process_colon_member(stmt)
          class_id = qualify_name(class_id_text(stmt[:class_id]))

          entity = find_or_create_entity(class_id)
          apply_generic(entity, stmt[:generic])

          add_member(entity, stmt)
        end

        def process_class_body(entity, body_data)
          return unless body_data.is_a?(Array)

          body_data.each do |member_item|
            next unless member_item.is_a?(Hash)

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
          if item[:member][:method_name]
            add_method_to_entity(entity, item[:member], visibility)
          else
            add_attribute_to_entity(entity, item[:member], visibility)
          end
        end

        # Text the structured member rules did not read. mmdc calls it a
        # method when it holds a `)` and refuses a `)` outside the shape
        # `name(...) type`. The `*` and `$` marks it allows after an
        # attribute or method have no place in the model and are dropped.
        def add_raw_member(entity, text)
          text = text.strip
          visible = text.match(/\A(?<symbol>[-+#~])\s*(?<rest>\S.*)\z/m)
          visibility = visible ? VISIBILITY_SYMBOLS.fetch(visible[:symbol]) : 'public'
          text = visible[:rest] if visible
          call = text.match(RAW_METHOD)
          if call && !call[:name].strip.empty?
            entity.class_methods << raw_method(call, visibility)
          elsif text.include?(')')
            raise Parser::ParseError, "Cannot read #{text.inspect} as a class member."
          else
            entity.attributes << Diagram::ClassAttribute.new(name: text.sub(/\s*[*$]\z/, ''), visibility: visibility)
          end
        end

        # The `*` (abstract) and `$` (static) mmdc allows after a method have
        # no place in the model and are dropped. The mark only reads as a
        # classifier when it touches the closing `)` directly; a space
        # before it (`foo() $bar`) means `$bar` is the return type text, not
        # a marked-then-typed method.
        def raw_method(call, visibility)
          return_type = call[:rest].sub(/\A[*$]?\s*/, '').sub(/\s*[*$]\z/, '')
          Diagram::ClassMethod.new(
            name: call[:name].strip, parameters: call[:params],
            return_type: return_type.empty? ? nil : return_type,
            visibility: visibility
          )
        end

        def add_method_to_entity(entity, method_data, visibility)
          method_name = extract_text(method_data[:method_name])
          parameters = method_data[:parameters] ? extract_text(method_data[:parameters]) : ''
          return_type = nil

          if method_data[:return_type] && method_data[:return_type][:type]
            return_type = extract_text(method_data[:return_type][:type])
          end

          method = Diagram::ClassMethod.new.tap do |m|
            m.name = method_name
            m.parameters = parameters
            m.return_type = return_type
            m.visibility = visibility
          end

          entity.class_methods << method
        end

        def add_attribute_to_entity(entity, attr_data, visibility)
          attr_name = extract_text(attr_data[:attr_name])
          attr_type = attr_data[:type] ? extract_text(attr_data[:type]) : nil

          attribute = Diagram::ClassAttribute.new.tap do |attr|
            attr.name = attr_name
            attr.type = attr_type
            attr.visibility = visibility
          end

          entity.attributes << attribute
        end

        def process_relationship(stmt)
          from_id = class_id_text(stmt[:from_id])
          to_id = class_id_text(stmt[:to_id])
          operator = extract_text(stmt[:operator][:arrow])

          # Qualify names if in namespace
          from_id = qualify_name(from_id)
          to_id = qualify_name(to_id)

          # Ensure both entities exist
          apply_generic(ensure_entity_exists(from_id), stmt[:from_generic])
          apply_generic(ensure_entity_exists(to_id), stmt[:to_generic])

          # Get relationship type
          relationship_type = RELATIONSHIP_TYPES[operator]
          relationship_type ||= 'association'

          # Parse cardinality
          source_card = nil
          target_card = nil

          if stmt[:source_card]
            source_card = extract_text(stmt[:source_card][:string])
          end

          if stmt[:target_card]
            target_card = extract_text(stmt[:target_card][:string])
          end

          # Parse label
          label = nil
          if stmt[:pipe_label] && stmt[:pipe_label][:label_text]
            label = extract_text(stmt[:pipe_label][:label_text])
            # Strip surrounding quotes if present
            label = label.gsub(/^["']|["']$/, '') if label
          elsif stmt[:colon_label] && stmt[:colon_label][:label_text]
            label = extract_text(stmt[:colon_label][:label_text]).strip
          end

          # Determine direction
          # For left-pointing arrows, reverse the relationship
          if LEFT_POINTING.include?(operator)
            actual_from = to_id
            actual_to = from_id
            # Swap cardinalities
            actual_source_card = target_card
            actual_target_card = source_card
          else
            actual_from = from_id
            actual_to = to_id
            actual_source_card = source_card
            actual_target_card = target_card
          end

          mixed_markers = mixed_markers_for(operator)

          relationship = Diagram::ClassRelationship.new.tap do |rel|
            rel.from_id = actual_from
            rel.to_id = actual_to
            rel.relationship_type = relationship_type
            rel.label = label
            rel.source_cardinality = actual_source_card
            rel.target_cardinality = actual_target_card
            if mixed_markers
              rel.start_marker = mixed_markers[:start_marker]
              rel.end_marker = mixed_markers[:end_marker]
              rel.dashed = mixed_markers[:dashed]
            end
          end

          @diagram.relationships << relationship
        end

        # Looks up an `o..`-style single-marker operator by literal string,
        # or decomposes a genuine two-way operator (a marker on both ends)
        # structurally via MARKER_TYPES. `nil` for every single-sided
        # operator, which keeps its existing RELATIONSHIP_TYPES rendering.
        def mixed_markers_for(operator)
          return MIXED_MARKER_ENDPOINTS[operator] if MIXED_MARKER_ENDPOINTS.key?(operator)

          match = MIXED_OPERATOR_PATTERN.match(operator)
          return nil unless match

          {
            start_marker: MARKER_TYPES.fetch(match[:left]),
            end_marker: MARKER_TYPES.fetch(match[:right]),
            dashed: match[:link] == '..'
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
          return unless creating && generic.is_a?(Hash) && generic[:generic_type]
          return if @labelled_ids.include?(entity.id)

          entity.name = "#{entity.name}~#{extract_text(generic[:generic_type])}~"
        end

        def qualify_name(name)
          return name unless @current_namespace
          return name if name.include?('.')

          "#{@current_namespace}.#{name}"
        end

        def parse_visibility(vis_data)
          return 'public' unless vis_data

          symbol = extract_text(vis_data[:vis_symbol])
          VISIBILITY_SYMBOLS[symbol] || 'public'
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:arrow]
              value[:arrow].to_s
            elsif value[:stereotype_value]
              value[:stereotype_value].to_s
            elsif value[:dir_value]
              value[:dir_value].to_s
            elsif value[:label_text]
              value[:label_text].to_s
            elsif value[:vis_symbol]
              value[:vis_symbol].to_s
            elsif value[:type]
              value[:type].to_s
            elsif value[:attr_name]
              value[:attr_name].to_s
            elsif value[:method_name]
              value[:method_name].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end
        end
      end
    end
  end
end