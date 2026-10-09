# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A `package` block around declared classes. `id` is what the source
      # calls it, `title` the text drawn (the quoted name in
      # `package "Title" as id`), `shape` is :folder or :frame (`<<Frame>>`)
      # and `icon` is true for the `+` written before the keyword.
      class Package
        attr_reader :id, :title, :shape, :icon

        def initialize(id:, title:, shape:, icon:)
          @id = id
          @title = title
          @shape = shape
          @icon = icon
          freeze
        end
      end
    end
  end
end
