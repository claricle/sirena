# frozen_string_literal: true

require "parslet"

require_relative "../metadata_yaml"

module Sirena
  module Parser
    module Builders
      # Transform for Kanban diagrams
      class Kanban < Parslet::Transform
        # Helper class to build kanban board from indented lines
        class BoardBuilder
          attr_reader :columns

          def initialize
            @columns = []
            @current_column = nil
            @items = []
            @anonymous_index = 0
          end

          def add_line(line_data)
            return apply_modifier(:icon, line_data[:icon].to_s) if line_data[:icon]
            return apply_modifier(:classes, line_data[:classes].to_s.strip.split(/\s+/)) if line_data[:classes]

            indent_size = get_indent_size(line_data[:indent])

            id = resolve_id(line_data[:id])

            # An item with no bracket label displays its id, which is what
            # mermaid renders. Resolved here, once: add_card reads this field
            # directly, and add_column reads it through column_title, which
            # may override it with a `label:` from the metadata.
            #
            # The metadata is parsed here rather than in add_card so that
            # add_column can consult it too; parse_metadata returns {} for a
            # nil subtree, so this is always a Hash.
            #
            # `|| id` relies on an absent label being nil rather than "",
            # since `""` is truthy in Ruby and would not fall back. That
            # holds only because labelled_item and shaped_item capture with
            # `repeat(1)`, so a label that matched is never empty.
            @items << {
              id: id,
              text: line_data[:text]&.to_s || id,
              indent: indent_size,
              metadata: parse_metadata(line_data[:metadata]),
            }
          end

          def finalize
            return if @items.empty?

            # The first item's indent is the column level, as in mermaid's
            # getSection. An item at that indent is a column; any other
            # indent is a card of the latest column, including one LESS
            # indented than the first. Mermaid rejects a less-indented item
            # only once another item follows it.
            column_indent = @items.first[:indent]
            shallower = nil

            @items.each do |item|
              if shallower
                raise Parser::ParseError,
                      "Items without section detected, " \
                      "found section (\"#{column_title(shallower)}\")."
              end

              shallower = item if item[:indent] < column_indent

              if item[:indent] == column_indent
                add_column(item)
              else
                add_card(item)
              end
            end
          end

          private

          # A shape with no id (`(text)`) never captures `:id`. Mermaid
          # still draws it - it auto-assigns one - so this does too,
          # deterministically: parsing the same source twice must produce
          # the same diagram, and a random id would break that on every
          # call (see the `kanban-1` / `kanban-2` assertions in
          # spec/sirena/parser/kanban_spec.rb). Unlike
          # Builders::Block.anonymous_id, this id is never displayed -
          # `unlabelled_shaped_item` always captures its own `:text`, so
          # `resolve_id`'s output never reaches TextMeasurement and its
          # length has no effect on layout (measured: extending it by
          # 1,000 characters left the rendered SVG byte-identical). The
          # hyphen keeps generated ids out of the author's namespace,
          # since identifier_char is `[a-zA-Z0-9_]` and can never spell
          # one.
          def resolve_id(id_slice)
            return id_slice.to_s if id_slice

            @anonymous_index += 1
            "kanban-#{@anonymous_index}"
          end

          def add_column(item)
            column = {
              id: item[:id],
              title: column_title(item),
              icon: item[:metadata][:icon],
              classes: normalize_classes(item[:metadata][:classes]),
              cards: [],
            }

            @columns << column
            @current_column = column
          end

          # `::icon(...)`/`:::` lines modify whichever item was added last;
          # raise rather than silently drop when there is none, matching
          # mmdc 11.12.0 (which rejects that shape). Both keys are
          # last-write-wins, matching mermaid's `decorateNode`, which
          # plainly assigns `node.cssClasses = ...` rather than merging.
          def apply_modifier(key, value)
            raise Parser::ParseError, "#{key == :icon ? '::icon' : ':::'} with no preceding item." unless @items.last

            @items.last[:metadata][key] = value
          end

          # `classes` arrives here as an Array from a `:::a b` directive line
          # (parse_metadata drops a scalar `classes:` key from `@{ ... }`
          # metadata entirely - mermaid does not read one). `else` also covers a
          # nil/absent value, normalized to an empty Array. The single point
          # both add_column and add_card read from.
          def normalize_classes(value)
            case value
            when Array then value
            else value.to_s.strip.split(/\s+/)
            end
          end

          # The card's own `id` and `text` beat a metadata entry of the same
          # name, because mermaid ignores `@{ id: ... }` and `@{ text: ... }`.
          # Merging the metadata FIRST makes that true by construction, with
          # no exclusion list to keep in step as fields are added.
          #
          # A `label:` on a card is kept as its own attribute and drawn as a
          # separate "Label:" row. That diverges from mermaid, which renders
          # the label as the card's primary text and draws no such row. The
          # divergence is pre-existing; correcting it belongs to the
          # card-conformance bucket.
          def add_card(item)
            @current_column[:cards] << item[:metadata].merge(
              id: item[:id],
              text: item[:text],
              classes: normalize_classes(item[:metadata][:classes]),
            )
          end

          # A `label:` replaces a COLUMN's display text, which is what mermaid
          # renders. A label mermaid would treat as unset is already gone by
          # here - parse_metadata drops it - so falling back to the bracket
          # text, or to the id, is a plain `||`.
          def column_title(item)
            item[:metadata][:label] || item[:text]
          end

          # `Kanban.metadata_fields` does the real work - a real YAML engine
          # for structure and resolution - so this is left only to route each
          # resolved key to the card/column field mermaid's `addNode` reads
          # it into.
          def parse_metadata(metadata_data)
            return {} if metadata_data.nil?

            result = {}

            Kanban.metadata_fields(metadata_data).each do |key, value|
              case key
              when "assigned"
                result[:assigned] = value
              when "ticket"
                result[:ticket] = value
              when "icon"
                result[:icon] = value
              when "label"
                result[:label] = value
              when "priority"
                result[:priority] = value
              when "classes"
                # Mermaid's `addNode` reads shape/label/icon/assigned/ticket/
                # priority out of `@{ ... }` metadata and nothing else -
                # `classes` is not a recognized key there (verified against
                # the installed @mermaid-js/mermaid-cli 11.12.0
                # kanban-definition bundle). Only a `:::` directive
                # (apply_modifier) may set classes; a scalar `@{ classes: ... }`
                # entry is dropped, matching mermaid.
                next
              else
                # Store unknown keys as-is
                result[key.to_sym] = value
              end
            end

            result
          end

          def get_indent_size(indent_data)
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            indent_str = if indent_data.is_a?(Array)
                           indent_data.join("")
                         else
                           indent_data.to_s
                         end

            indent_str.length
          end
        end

        # The `@{ ... }` body, resolved by a real YAML engine
        # (`MetadataYaml`) the way mermaid's js-yaml does: flow vs block is
        # decided by whether the body contains a newline anywhere. Do not
        # re-add hand-written grammar rules for YAML legality - duplicate
        # keys and tab indentation are refused by the engine.
        #
        # @raise [Parser::ParseError] on YAML mermaid would also refuse
        def self.metadata_fields(metadata_data)
          document, unshield = shield_foreign_breaks(
            metadata_document(metadata_data),
          )
          resolved = MetadataYaml.value(document)
          raise Parser::ParseError, "Empty metadata." if resolved.nil?
          return {} unless resolved.is_a?(Hash)

          stored_fields(resolved)
            .to_h { |key, text| [unshield.call(key), unshield.call(text)] }
        end

        # Mermaid's own wrapping: a single-line body becomes a flow
        # mapping between braces, a multiline one is used as written -
        # see Builders::Flowchart#metadata_document, the same rule.
        def self.metadata_document(metadata_data)
          text = metadata_body_text(metadata_data)
          body = break_quoted_newlines(strip_metadata_comments(text))
          body.include?("\n") ? "#{body}\n" : "{\n#{body}\n}"
        end
        private_class_method :metadata_document

        # NEL, LS and PS are line breaks to Psych but ordinary characters
        # to js-yaml, and `MetadataYaml` refuses them rather than read them
        # the wrong way. Mermaid keeps them as text, so they are swapped for
        # unused private-use characters while the engine reads the body, and
        # swapped back in the stored fields.
        #
        # @return [Array(String, #call)] the shielded body and the function
        #   that restores a stored string
        def self.shield_foreign_breaks(document)
          present = FOREIGN_BREAKS.select { |char| document.include?(char) }
          return [document, :itself.to_proc] if present.empty?

          shields = present.zip(spare_characters(document, present.size)).to_h
          [document.gsub(Regexp.union(present), shields), unshielder(shields)]
        end
        private_class_method :shield_foreign_breaks

        def self.unshielder(shields)
          restore = shields.invert
          pattern = Regexp.union(restore.keys)
          ->(text) { text.gsub(pattern, restore) }
        end
        private_class_method :unshielder

        # A character is spare when the body neither contains it nor spells
        # it as a `\xHH`, `\uHHHH` or `\UHHHHHHHH` escape - an escape
        # would otherwise resolve to it and be swapped back by mistake.
        def self.spare_characters(document, count)
          taken = taken_code_points(document)
          free = (0xE000..0xF8FF).lazy.reject { |code| taken.include?(code) }
          spare = free.first(count).map { |code| code.chr(Encoding::UTF_8) }
          return spare if spare.size == count

          raise Parser::ParseError, "Unreadable line break."
        end
        private_class_method :spare_characters

        def self.taken_code_points(document)
          literal = document.scan(/[\ue000-\uf8ff]/).map(&:ord)
          escaped = document.scan(YAML_CODE_ESCAPE).flatten.compact
          literal + escaped.map { |hex| hex.to_i(16) }
        end
        private_class_method :taken_code_points

        # A list or map is text only under the keys mermaid draws; `shape`
        # refuses it (`validate_shape`) and any other key ignores it.
        # `priority` is one of those: mermaid compares it by identity, so
        # `[High]` is not the priority `High`. The one `walk` budget covers
        # the whole body.
        def self.stored_fields(resolved)
          walk = { left: JS_LIST_ITEMS }
          resolved.filter_map do |key, value|
            next if dropped_by_mermaid?(value)

            validate_shape(value) if key == "shape"
            next if collection?(value) && !TEXT_KEYS.include?(key)

            [key, js_text(value, walk)]
          end.to_h
        end
        private_class_method :stored_fields

        def self.collection?(value)
          value.is_a?(Array) || value.is_a?(Hash)
        end
        private_class_method :collection?

        def self.validate_shape(value)
          unless value.is_a?(String)
            raise Parser::ParseError,
                  "Unusable shape in metadata."
          end
          return if value == value.downcase && !value.include?("_")

          raise Parser::ParseError,
                "No such shape: #{value}. Shape names should be lowercase."
        end
        private_class_method :validate_shape

        # An empty repeat captures as [], not as an empty slice.
        def self.metadata_body_text(metadata_data)
          value = metadata_data[:body]
          value.is_a?(Array) ? "" : value.to_s
        end
        private_class_method :metadata_body_text

        # Mermaid strips comments before lexing, so metadata never sees
        # them - `%%{` is a directive rather than a comment and stays.
        # Uses JavaScript's whitespace set, matching Mermaid's comment pass.
        def self.strip_metadata_comments(body)
          body.gsub(/(?<=\n)#{JS_SPACE}*%%(?!\{)[^\n]+\n?/o, "")
        end
        private_class_method :strip_metadata_comments

        # The kanban lexer rewrites line breaks inside double-quoted
        # metadata before handing the body to js-yaml.
        def self.break_quoted_newlines(body)
          body.gsub(/"[^"]*"/) { |run| run.gsub(QUOTED_BREAK, "<br/>") }
        end
        private_class_method :break_quoted_newlines

        JS_SPACE = '[\t\n\v\f\r \u00a0\u1680\u2000-\u200a' \
                   '\u2028\u2029\u202f\u205f\u3000\ufeff]'
        QUOTED_BREAK = /\n#{JS_SPACE}*/
        FOREIGN_BREAKS = ["\u0085", "\u2028", "\u2029"].freeze
        YAML_CODE_ESCAPE = /\\(?:x(\h{2})|u(\h{4})|U(\h{8}))/
        JS_LIST_ITEMS = 10_000
        JS_LIST_DEPTH = 256
        TEXT_KEYS = %w[assigned ticket icon label].freeze

        private_constant :JS_SPACE, :QUOTED_BREAK, :FOREIGN_BREAKS,
                         :YAML_CODE_ESCAPE, :JS_LIST_ITEMS, :JS_LIST_DEPTH,
                         :TEXT_KEYS

        # `null`, `false`, `0` and `""` are all falsy to mermaid, which
        # skips the key rather than failing on it - the same table
        # Builders::Flowchart#truthy? applies to its own resolved values.
        def self.dropped_by_mermaid?(value)
          case value
          when nil, false, 0, "" then true
          else value.is_a?(Float) && value.nan?
          end
        end
        private_class_method :dropped_by_mermaid?

        # Mermaid draws `.toString()` of what js-yaml resolved: numbers and
        # booleans as JavaScript prints them (`0x10` is "16"), a list as its
        # items joined by commas (`[one, two]` is "one,two"), a map as
        # "[object Object]". An alias repeats a list by reference, so
        # `JS_LIST_ITEMS` caps the items joined and `JS_LIST_DEPTH` the
        # nesting, as `Source::Frontmatter` bounds its own walk; mmdc draws
        # some bodies this refuses.
        #
        # @param walk [Hash] items still allowed to be joined, body-wide
        # @param ancestors [Array<Array>] lists being joined; one holding
        #   itself joins as "" the way JavaScript's `join` does
        def self.js_text(value, walk, ancestors = [])
          case value
          when Numeric then Sirena::JsNumber.stringify(value)
          when Hash then "[object Object]"
          when Array then js_join(value, walk, ancestors)
          else value.to_s
          end
        end
        private_class_method :js_text

        def self.js_join(list, walk, ancestors)
          return "" if ancestors.any? { |outer| outer.equal?(list) }

          refuse_list("nested too deeply") if ancestors.size >= JS_LIST_DEPTH
          list.map do |item|
            walk[:left] -= 1
            refuse_list("too large") if walk[:left].negative?

            js_text(item, walk, ancestors + [list])
          end.join(",")
        end
        private_class_method :js_join

        def self.refuse_list(reason)
          raise Parser::ParseError, "Metadata list #{reason}."
        end
        private_class_method :refuse_list

        # Transform the lines array into columns and cards
        rule(lines: subtree(:lines)) do
          builder = BoardBuilder.new
          lines_array = Array(lines)

          lines_array.each do |line_data|
            # An empty line never captures anything, so it contributes no
            # entry at all to this array rather than a Hash lacking keys -
            # this Hash check is the only filter empty lines need. It is
            # NOT a stand-in for requiring `:id`: an unlabelled shaped item
            # (`(text)`) is a Hash with no `:id` key and is a real item.
            next unless line_data.is_a?(Hash)

            builder.add_line(line_data)
          end

          builder.finalize

          {
            columns: builder.columns,
          }
        end
      end
    end
  end
end
