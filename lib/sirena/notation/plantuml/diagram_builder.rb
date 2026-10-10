# frozen_string_literal: true

require_relative "class_name"
require_relative "diagram"
require_relative "klass"
require_relative "member"
require_relative "note"
require_relative "package"
require_relative "style_reader"
require_relative "relation"
require_relative "unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      # Collects what the parser reads, one line at a time, into a Diagram.
      #
      # A class mentioned in a relation before (or without) being declared
      # exists as an implicit :class. A later declaration may give it its
      # kind; redeclaring an explicitly declared class as another kind is
      # refused, because this notation cannot say what it means.
      #
      # Source with only `-->` and `<--` relations is a sequence diagram to
      # PlantUML and is refused; see `class_only?` and `GLOBAL_COMMAND`.
      class DiagramBuilder
        # The words PlantUML 1.2026.6 reads as a global command, not a
        # participant, at the start of a sequence-diagram line.
        GLOBAL_COMMAND =
          /\A(?:caption|footer|header|legend|mainframe|title)[ \t]/i

        def initialize
          @kinds = {}
          @bodies = {}
          @explicit = {}
          @relations = []
          @junctions = []
          @directives = []
          @extras = {}
          @notes = []
          @hidden_tags = []
          @packages = []
          @captions = {}
        end

        # A kind written twice keeps the later text, as PlantUML does.
        def caption(caption)
          @captions[caption.kind] = caption
        end

        # @raise [UnsupportedConstructError] on a second block, whose
        #   precedence over the first is not read
        def open_style(number, text)
          refuse(text, number, "second style block") if @style_reader

          @style_line = number
          @style_reader = StyleReader.new
        end

        # @return [Symbol] :closed when the line ended the block, else :open
        def style_line(text, number)
          @style_reader.feed(text, number)
        end

        # @return [Integer, nil] the line of the style block opened last
        def open_style_line
          @style_line
        end

        def directive(text)
          @directives << text
        end

        # `hide $tag` removes every class carrying the tag, whether the
        # class is declared before or after the line.
        def hide_tag(tag, number, text)
          @hidden_tags << [tag, number, text]
        end

        # Opens a package; the classes declared until {#close_package} are
        # in it, and a package opened before then is inside it.
        def open_package(package, number, text)
          if @packages.any? { |known| known.id == package.id }
            refuse(text, number, "package declared twice")
          end

          parent = implicit_parents(package.id, number, text)
          @packages << package.inside(parent)
          scopes.push([package, number, text])
        end

        def package_open?
          !scopes.empty?
        end

        # @raise [UnsupportedConstructError] when the package holds no class,
        #   directly or in a package inside it
        def close_package
          package, number, text = scopes.pop
          members = @extras.values.count do |entry|
            chain_of(entry[:package]).include?(package.id)
          end
          refuse(text, number, "empty package") if members.zero?
        end

        # @return [Integer, nil] the line of the innermost package still open
        def open_package_line
          scopes.last && scopes.last[1]
        end

        def junction(junction, number, text)
          mention(junction.owner)
          @junctions << [junction, number, text]
        end

        # @return [Array(String, Integer)] the class whose body was opened
        #   last and the line it was opened on
        def open_class
          @open
        end

        # Opens a note; its text arrives through {#add_note_line}.
        # @raise [Sirena::Parser::ParseError] when the class is unknown, as
        #   PlantUML refuses a note on a class not yet mentioned
        def open_note(head, number, lines = [])
          unless @kinds.key?(head[:target])
            raise Sirena::Parser::ParseError,
                  "Parse error: line #{number} puts a note on " \
                  "#{head[:target]}, which is not declared before it"
          end

          @note = [head, number, lines]
        end

        def add_note_line(text)
          @note.last << text
        end

        def close_note
          head, _number, lines = @note
          @notes << Note.new(head, lines: lines.freeze)
          @note = nil
        end

        # @return [Integer, nil] the line the unclosed note was opened on
        def open_note_line
          @note && @note[1]
        end

        # @return [Boolean] true until a class is declared or mentioned
        def empty?
          @kinds.empty?
        end

        # Declares a class and, when `entry[:body]` is true, opens its body.
        # `entry` holds :name, :kind, :body, :generics and :stereotypes.
        def declare(entry, number, text)
          name, kind = entry.values_at(:name, :kind)
          home = home_of(name, number, text)
          refuse_package_clash(name, home, number, text)
          mention(name)
          refuse_redeclaration(name, kind, number, text)
          record_class(name, kind, entry.merge(package: home))
          @open = [name, number] if entry[:body]
        end

        def record_class(name, kind, entry)
          @kinds[name] = kind
          @explicit[name] = true
          @class_evidence = true
          @extras[name] = entry.slice(:generics, :stereotypes, :tags, :package)
        end

        def add_member(member)
          @bodies.fetch(@open.first) << member
        end

        def relate(relation, number, text)
          refuse_new_class_in_package(relation, number, text)
          refuse_new_qualified_class(relation, number, text)
          [relation.left, relation.right].each { |name| mention_end(name) }
          @sequence_arrow ||= [number, text] if sequence_arrow?(relation, text)
          @class_evidence ||= class_only?(relation)
          @relations << relation
        end

        # @return [Diagram] frozen, with every class once in order of first
        #   mention
        # @raise [UnsupportedConstructError] when PlantUML would read the
        #   source as a sequence diagram
        def diagram
          refuse_sequence_diagram
          @junctions.each { |entry| refuse_unrelated_junction(*entry) }

          visible(build_classes)
        end

        private

        def build_classes
          @kinds.map do |name, kind|
            body = @bodies.fetch(name).dup.freeze
            Klass.new(name: name, kind: kind, body: body,
                      **@extras.fetch(name, {}))
          end
        end

        def visible(classes)
          hidden = classes.select { |klass| hidden?(klass) }.map(&:name)
          refuse_attachments_to(hidden)
          kept = classes.reject { |klass| hidden.include?(klass.name) }
          gone = hidden + unoccupied_ids(kept)
          assemble(kept, @relations.reject { |rel| touches?(rel, gone) })
        end

        def assemble(classes, relations)
          Diagram.new(
            classes: classes.freeze, relations: relations.freeze,
            junctions: @junctions.map(&:first).freeze,
            directives: @directives.dup.freeze, notes: @notes.dup.freeze,
            packages: occupied_packages(classes).freeze,
            captions: @captions.values.freeze, style: style_sheet
          )
        end

        def style_sheet
          @style_reader ? @style_reader.sheet : StyleSheet.new
        end

        # A package whose every class is hidden draws no frame.
        def occupied_packages(classes)
          named = occupied_ids(classes)
          @packages.select { |package| named.include?(package.id) }
        end

        def unoccupied_ids(classes)
          @packages.map(&:id) - occupied_ids(classes)
        end

        def occupied_ids(classes)
          classes.flat_map { |klass| chain_of(klass.package) }
        end

        def chain_of(id)
          Package.chain(id, @packages)
        end

        # `package a.b.c` also opens `a` and `a.b`, each inside the one
        # before. Returns the id the package itself sits inside.
        def implicit_parents(id, number, text)
          *outer, _leaf = id.split(".")
          outer.each_index.reduce(scope_id) do |parent, index|
            id = outer.first(index + 1).join(".")
            open_implicit(id, parent, number, text)
            id
          end
        end

        def open_implicit(id, parent, number, text)
          known = @packages.find { |other| other.id == id }
          if known.nil?
            @packages << Package.new(id: id, title: id.split(".").last,
                                     shape: :folder, icon: false,
                                     parent: parent)
          elsif known.parent != parent
            refuse(text, number, "package name shared by two packages")
          end
        end

        # The package a class lives in. A name written with dots lives in
        # the namespaces before its last dot, which PlantUML opens itself.
        def home_of(name, number, text)
          return scope_id unless name.include?(".")

          refuse_misplaced_qualified(name, number, text)
          implicit_parents(name, number, text)
        end

        def refuse_misplaced_qualified(name, number, text)
          unless scopes.empty? && name.split(".", -1).none?(&:empty?)
            refuse(text, number, "qualified class name here")
          end
          return unless ClassName.namespaces(name).any? { _1.include?("\\") }

          refuse(text, number, "escape in a namespace name")
        end

        def package?(name)
          @packages.any? { |package| package.id == name }
        end

        def scopes
          @scopes ||= []
        end

        def scope_id
          scopes.last&.first&.id
        end

        def hidden?(klass)
          @hidden_tags.any? { |tag, *| klass.tags.include?(tag) }
        end

        def touches?(relation, names)
          names.include?(relation.left) || names.include?(relation.right)
        end

        # PlantUML's result for a note or association class on a hidden
        # class is not measured, so it is not drawn.
        def refuse_attachments_to(hidden)
          attached = @junctions.map { |junction, *| junction.owner }
          owners = attached + @notes.map(&:target)
          return unless owners.intersect?(hidden)

          _tag, number, text = @hidden_tags.first
          raise UnsupportedConstructError.new(
            construct: "hide of a class with a note or association class",
            line: number, text: text
          )
        end

        def refuse_sequence_diagram
          return unless @sequence_arrow && !@class_evidence

          number, text = @sequence_arrow
          raise UnsupportedConstructError.new(
            construct: "sequence diagram", line: number, text: text,
          )
        end

        # PlantUML joins the two classes itself when no relation was
        # written; this notation has no relation to hang the class on.
        def refuse_unrelated_junction(junction, number, text)
          pair = [junction.from, junction.to].sort
          return if @relations.any? { |r| [r.left, r.right].sort == pair }

          raise UnsupportedConstructError.new(
            construct: "association class without its relation",
            line: number, text: text
          )
        end

        def refuse(text, number, construct)
          raise UnsupportedConstructError.new(
            construct: construct, line: number, text: text,
          )
        end

        # A class lives in one place; a name met outside its package would
        # be a second class to PlantUML.
        def refuse_package_clash(name, home, number, text)
          refuse(text, number, "class named like a package") if package?(name)
          return unless @kinds.key?(name)
          return if @extras.dig(name, :package) == home

          refuse(text, number, "class declared in more than one place")
        end

        def refuse_new_class_in_package(relation, number, text)
          return if scopes.empty?
          return if [relation.left, relation.right].all? { |name| @kinds[name] }

          refuse(text, number, "class first mentioned in a package")
        end

        # A qualified name met before it is declared would put the class
        # outside the namespaces PlantUML gives it.
        def refuse_new_qualified_class(relation, number, text)
          [relation.left, relation.right].each do |name|
            next if !name.include?(".") || @kinds.key?(name) || package?(name)

            refuse(text, number, "qualified class name first mentioned " \
                                 "in a relation")
          end
        end

        def refuse_redeclaration(name, kind, number, text)
          return unless @explicit[name] && @kinds[name] != kind

          raise UnsupportedConstructError.new(
            construct: "redeclaration as another kind", line: number,
            text: text
          )
        end

        def sequence_arrow?(relation, text)
          !class_only?(relation) && !GLOBAL_COMMAND.match?(text)
        end

        # True when only a class diagram has this relation: a multiplicity, or
        # an arrow other than a plain `-->` or `<--`.
        def class_only?(relation)
          return true if relation.left_multiplicity
          return true if relation.right_multiplicity

          !relation.plain?
        end

        # A name that is a package's id, with no class of that name, is the
        # package: the relation runs to its frame.
        def mention_end(name)
          return if !@kinds.key?(name) && package?(name)

          mention(name)
        end

        def mention(name)
          @kinds[name] ||= :class
          @bodies[name] ||= []
        end
      end
    end
  end
end
