# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module IR
    class Model < Lutaml::Model::Serializable
      def initialize(attributes = {})
        unless attributes.is_a?(Hash)
          raise ArgumentError, "attributes must be a Hash"
        end

        normalized = normalize_keys(attributes)
        unknown = normalized.keys - self.class.attributes.keys
        unless unknown.empty?
          raise ArgumentError, "unknown attributes: #{unknown.sort.join(', ')}"
        end

        super(normalized)
      end

      def validate(register: Lutaml::Model::Config.default_register)
        super + semantic_errors
      end

      def valid?
        validate.empty?
      end

      private

      def semantic_errors
        []
      end

      def validation_error(message)
        ArgumentError.new(message)
      end

      def normalize_keys(attributes)
        normalized = attributes.transform_keys do |key|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise ArgumentError, "attribute names must be Strings or Symbols"
          end

          key.to_sym
        end
        if normalized.length != attributes.length
          raise ArgumentError, "duplicate attribute names"
        end

        normalized
      end
    end
  end
end
