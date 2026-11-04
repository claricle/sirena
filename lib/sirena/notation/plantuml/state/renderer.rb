# frozen_string_literal: true

require_relative "../../../renderer/state_diagram"

module Sirena
  module Notation
    module PlantUML
      module State
        # Draws a state scene with its transitions above the states, so a
        # transition inside a composite is not painted over by the
        # composite's own fill.
        class Renderer < Sirena::Renderer::StateDiagram
          def render(scene)
            require_typed_scene!(scene)
            svg = create_document(scene)
            render_states(scene, svg)
            render_transitions(scene, svg)
            svg
          end
        end
      end
    end
  end
end
