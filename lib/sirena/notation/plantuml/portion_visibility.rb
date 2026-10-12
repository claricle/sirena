# frozen_string_literal: true

require_relative "klass"

module Sirena
  module Notation
    module PlantUML
      # What the `hide` and `show` lines take out of a class: its fields,
      # its methods or its stereotype labels. A line names every class, one
      # class, or the classes carrying a `<<stereotype>>`; for the
      # stereotype portion a `<<stereotype>>` target hides only that label.
      # Lines apply in source order wherever the class is declared, and a
      # later line overrides an earlier one, as in PlantUML.
      #
      # `hide empty members` and `hide circle` change only how a class is
      # drawn, so they are not read here.
      class PortionVisibility
        RULE = /\A(hide|show)[ \t]+
                (?:(?!empty[ \t])([A-Za-z_][A-Za-z0-9_]*|<<[^<>\s]+>>)[ \t]+)?
                (members|attributes|fields|methods|stereotype)\z/ix
        PORTIONS = {
          "members" => %i[field method], "attributes" => %i[field],
          "fields" => %i[field], "methods" => %i[method],
          "stereotype" => %i[stereotype]
        }.freeze
        private_constant :RULE, :PORTIONS

        # @param directives [Array<String>] the Diagram's directive lines
        def initialize(directives)
          @rules = directives.filter_map { |line| rule(line) }
        end

        # @return [Klass] `klass` without its hidden members and stereotype
        #   labels; `klass` itself when nothing is hidden
        def apply(klass)
          return klass if @rules.empty?

          Klass.new(
            name: klass.name, kind: klass.kind, package: klass.package,
            body: klass.body.select { |member| member?(klass, member) }.freeze,
            stereotypes: stereotypes(klass), generics: klass.generics,
            tags: klass.tags
          )
        end

        private

        def rule(line)
          match = RULE.match(line)
          return unless match

          { show: match[1].casecmp?("show"), target: match[2],
            portions: PORTIONS.fetch(match[3].downcase) }
        end

        def member?(klass, member)
          shown?(member.kind) { |target| covers?(klass, target) }
        end

        def stereotypes(klass)
          klass.stereotypes.select do |label|
            shown?(:stereotype) do |target|
              target == "<<#{label}>>" || (!stereotype?(target) &&
                covers?(klass, target))
            end
          end.freeze
        end

        # The last rule for `portion` whose target the block accepts.
        def shown?(portion)
          @rules.reduce(true) do |shown, rule|
            next shown unless rule[:portions].include?(portion)

            yield(rule[:target]) ? rule[:show] : shown
          end
        end

        def covers?(klass, target)
          return true if target.nil?
          return klass.name == target unless stereotype?(target)

          klass.stereotypes.include?(target[2..-3])
        end

        def stereotype?(target)
          target&.start_with?("<<")
        end
      end
    end
  end
end
