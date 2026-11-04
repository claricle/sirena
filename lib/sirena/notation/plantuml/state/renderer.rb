# frozen_string_literal: true

require_relative "../../../renderer/state_diagram"
require_relative "../style"

module Sirena
  module Notation
    module PlantUML
      module State
        # Draws a state scene with its transitions above the states, so a
        # transition inside a composite is not painted over by the
        # composite's own fill. Every colour, font and line comes from the
        # diagram's {Style::Sheet}, whose defaults are PlantUML's own look.
        class Renderer < Sirena::Renderer::StateDiagram
          # @param style [Style::Sheet] the diagram's style
          def initialize(theme: nil, style: Style::Sheet.new)
            super(theme: theme)
            @style = style
          end

          def render(scene)
            require_typed_scene!(scene)
            svg = create_document(scene)
            paint_canvas(scene, svg)
            render_states(scene, svg)
            @owner = nil
            render_transitions(scene, svg)
            svg
          end

          protected

          def state_group(state)
            @owner = state
            super
          end

          private

          def paint_canvas(scene, svg)
            colour = @style.resolve(:document, :background)
            return if colour == "none"

            svg << Svg::Rect.new(x: 0, y: 0, width: scene.width,
                                 height: scene.height, fill: colour)
          end

          def look(property, state = @owner)
            @style.resolve(:state, property, id: state.id,
                                             stereotype: stereotype(state))
          end

          def stereotype(state)
            @style.element(state.id)[:stereotype]
          end

          # A state label takes the state's font; a transition's, the arrow's.
          def label_look(property)
            return look(property) if @owner

            @style.resolve(:arrow, property)
          end

          def final_state_shape(state)
            return super unless state.shape_type == "normal" ||
              state.shape_type.nil?

            outline(state)
          end

          # A composite's name sits in a bar above its children.
          def append_state_labels(state, group)
            group.children << header_rule(state) if state.children.any?
            super
          end

          def outline(state)
            Svg::Rect.new(x: state.x, y: state.y, width: state.width,
                          height: state.height,
                          fill: look(:background, state)).tap do |rect|
              stroke(rect, state)
              round(rect, state)
            end
          end

          def round(rect, state)
            radius = look(:round_corner, state)
            rect.rx = radius
            rect.ry = radius
          end

          def stroke(element, state)
            element.stroke = look(:border, state)
            element.stroke_width = look(:line_thickness, state).to_s
            dash = look(:line_style, state)
            element.stroke_dasharray = dash if dash
          end

          def header_rule(state)
            y = state.y + Hierarchy::HEADER
            Svg::Line.new(x1: state.x, y1: y, x2: state.x + state.width,
                          y2: y).tap { |line| stroke(line, state) }
          end

          def start_state_shape(state)
            super.tap do |circle|
              circle.fill = @style.resolve(:start, :background)
            end
          end

          def end_state_shape(state)
            super.tap do |group|
              ring, dot = group.children
              ring.stroke = @style.resolve(:start, :border)
              dot.fill = @style.resolve(:start, :background)
            end
          end

          def choice_state_shape(state)
            super.tap do |polygon|
              polygon.fill = look(:background, state)
              polygon.stroke = look(:border, state)
            end
          end

          def fork_join_state_shape(state)
            super.tap do |rect|
              rect.fill = @style.resolve(:start, :background)
            end
          end

          def transition_path(edge)
            super.tap do |path|
              path.stroke = @style.resolve(:arrow, :border)
              path.stroke_width = @style.resolve(:arrow, :line_thickness).to_s
            end
          end

          def apply_label_style(text, label)
            super
            text.fill = label_look(:font_colour)
            text.font_family = label_look(:font_name)
          end
        end
      end
    end
  end
end
