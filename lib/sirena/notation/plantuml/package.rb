# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A `package` block around declared classes. `id` is what the source
      # calls it, `title` the text drawn (the quoted name in
      # `package "Title" as id`), `shape` is :folder or :frame (`<<Frame>>`)
      # and `icon` is true for the `+` written before the keyword. `parent`
      # is the id of the package it is written inside, or nil.
      class Package
        attr_reader :id, :title, :shape, :icon, :parent

        def initialize(id:, title:, shape:, icon:, parent: nil)
          @id = id
          @title = title
          @shape = shape
          @icon = icon
          @parent = parent
          freeze
        end

        # @return [Array<String>] the ids of the packages around `id`,
        #   outermost first and `id` last; empty for nil
        def self.chain(id, packages)
          chain = []
          while id
            chain.unshift(id)
            id = packages.find { |package| package.id == id }&.parent
          end
          chain
        end

        # @return [Package] this package inside the package `parent`
        def inside(parent)
          self.class.new(id: id, title: title, shape: shape, icon: icon,
                         parent: parent)
        end
      end
    end
  end
end
