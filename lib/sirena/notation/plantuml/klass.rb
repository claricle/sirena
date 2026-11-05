# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A class, abstract class or interface and the Members of its
      # body, in the order they were written. `kind` is :class, :abstract or
      # :interface; `stereotypes` holds the text of each `<<...>>` and
      # `generics` the text of `<...>` after the name, or nil and `tags` the
      # names written as `$name` after the header and `package` the id of the
      # Package it was declared in, or nil. A body with no `--`-style rule
      # lists its fields before its methods whatever order they were written
      # in, as PlantUML draws it; a body with a rule keeps the written order.
      class Klass
        attr_reader :name, :kind, :body, :stereotypes, :generics, :tags,
                    :package

        # @param header [Hash] optional `:stereotypes`, `:generics` and
        #   `:tags`; each defaults to empty
        def initialize(name:, kind:, body:, package: nil, **header)
          @name = name
          @kind = kind
          @body = grouped(body)
          @package = package
          @stereotypes = header.fetch(:stereotypes, [].freeze)
          @generics = header[:generics]
          @tags = header.fetch(:tags, [].freeze)
          freeze
        end

        private

        def grouped(body)
          return body if body.any? { |member| member.kind == :separator }

          body.partition { |member| member.kind == :field }.flatten(1).freeze
        end
      end
    end
  end
end
