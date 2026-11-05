# frozen_string_literal: true

require "json"

module Sirena
  module Notation
    module PlantUML
      module Creole
        # The Open Iconic glyphs `<&name>` draws in a data diagram's cell:
        # outlines on an 8-unit grid, as PlantUML ships them.
        module Icons
          DATA = File.join(__dir__, "..", "plantuml_data", "openiconic.json")
          private_constant :DATA

          module_function

          def known?(name)
            outlines.key?(name)
          end

          # @return [String, nil] the outline's SVG path data
          def outline(name)
            outlines[name]
          end

          def outlines
            @outlines ||= JSON.parse(File.read(DATA)).freeze
          end
        end
      end
    end
  end
end
