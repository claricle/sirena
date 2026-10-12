# frozen_string_literal: true

require "psych"

module Sirena
  module Notation
    module Mermaid
      # Reads the Mermaid init setting that changes Class Diagram geometry:
      # the diagram-wide `fontFamily`, which sizes every class box.
      module ClassDiagramConfig
        INIT = /\A%%\{\s*init\s*:\s*(?<payload>.*)\s*\}%%\z/im
        private_constant :INIT

        module_function

        # @return [String, nil] the last init directive's `fontFamily`
        def font_family(directives)
          directives.reverse_each do |directive|
            family = family_of(directive)
            return family if family
          end
          nil
        end

        def family_of(directive)
          match = INIT.match(directive)
          return unless match

          config = Psych.safe_load(
            match[:payload], permitted_classes: [],
                             permitted_symbols: [], aliases: false
          )
          family = config["fontFamily"] if config.is_a?(Hash)
          family.to_s.strip unless family.to_s.strip.empty?
        rescue Psych::Exception
          nil
        end
        private_class_method :family_of
      end
    end
  end
end
