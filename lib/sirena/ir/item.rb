# frozen_string_literal: true

require_relative "model"
require_relative "property_set"

module Sirena
  module IR
    class Item < Model
      ROLE = /\A[a-z][a-z0-9_]*\z/
      PRIVATE_SPELLINGS = %w[mermaid plantuml puml].freeze

      attribute :id, :string
      attribute :label, :string
      attribute :role, :string
      attribute :parent_id, :string
      attribute :accessibility_title, :string
      attribute :accessibility_description, :string
      attribute :properties, PropertySet, default: -> { PropertySet.new }

      private

      def semantic_errors
        errors = []
        if id.nil? || id.empty?
          errors << validation_error("id must be a nonempty String")
        end
        unless properties&.valid?
          errors << validation_error("properties must be a valid PropertySet")
        end
        errors.concat(role_errors)
        errors
      end

      def role_errors
        return [] if role.nil?
        return [] if role.match?(ROLE) && notation_neutral_role?

        [validation_error("role must be a notation-neutral snake_case token")]
      end

      def notation_neutral_role?
        PRIVATE_SPELLINGS.none? { |word| role.include?(word) }
      end
    end
  end
end
