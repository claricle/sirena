# frozen_string_literal: true

require_relative "../../../renderer/state_diagram"
require_relative "../style"
require_relative "look"
require_relative "note_shape"

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
          # @param scale [Array(Float, Symbol), nil] a `scale` line: the
          #   number and what it sizes (:width, :height or :factor)
          def initialize(theme: nil, style: Style::Sheet.new, scale: nil)
            super(theme: theme)
            @style = style
            @scale = scale
          end

          def render(scene)
            require_typed_scene!(scene)
            @states = index(scene.children)
            svg = create_document(scene)
            apply_scale(svg)
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

          def index(states)
            states.each_with_object({}) do |state, found|
              found[state.id] = state
              found.merge!(index(state.children))
            end
          end

          # `scale` sizes the picture, not what is drawn: the viewBox keeps
          # the drawing's own units.
          def apply_scale(svg)
            return unless @scale

            value, axis = @scale
            factor = { width: value / svg.width, height: value / svg.height,
                       factor: value }.fetch(axis)
            svg.width *= factor
            svg.height *= factor
          end

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
            case state.shape_type
            when "note" then note_shape(state)
            when "history" then history_shape(state)
            when "normal", nil then outline(state)
            else super
            end
          end

          # A divider under the name of every plain state and composite.
          def append_state_labels(state, group)
            group.children << divider(state) if divided?(state)
            state.labels.each_with_index do |label, index|
              text = state_label(label)
              text.text_anchor = "start" if left_aligned?(state, index)
              group.children << text
            end
          end

          def divided?(state)
            [nil, "normal"].include?(state.shape_type)
          end

          def left_aligned?(state, index)
            state.shape_type == "note" || (index.positive? && divided?(state))
          end

          def history_shape(state)
            Svg::Circle.new(cx: state.x + (state.width / 2.0),
                            cy: state.y + (state.height / 2.0),
                            r: state.width / 2.0,
                            fill: look(:background, state)).tap do |circle|
              stroke(circle, state)
            end
          end

          # A pale sheet with a folded corner and a tail to its state.
          def note_shape(state)
            sheet = NoteShape.new(state,
                                  @states[state.id.split("----note").first])
            Svg::Group.new.tap do |group|
              [sheet.outline, sheet.fold].each do |data|
                group.children << note_path(data)
              end
            end
          end

          def note_path(data)
            Svg::Path.new(d: data,
                          fill: @style.resolve(:note,
                                               :background)).tap do |path|
              path.stroke = @style.resolve(:note, :border)
              path.stroke_width = @style.resolve(:note, :line_thickness).to_s
            end
          end

          # PlantUML fills only the name band of a composite left at the
          # default background and leaves its body clear; a colour the
          # diagram sets fills the whole composite.
          def outline(state)
            return banded_outline(state) if banded?(state)

            Svg::Rect.new(x: state.x, y: state.y, width: state.width,
                          height: state.height,
                          fill: look(:background, state)).tap do |rect|
              stroke(rect, state)
              round(rect, state)
            end
          end

          def banded?(state)
            state.children.any? &&
              look(:background, state) == Style::Defaults::BOX[:background]
          end

          def banded_outline(state)
            frame = Svg::Rect.new(x: state.x, y: state.y, width: state.width,
                                  height: state.height, fill: "none")
            stroke(frame, state)
            round(frame, state)
            Svg::Group.new.tap do |group|
              group.children << band(state)
              group.children << frame
            end
          end

          # The name band: rounded above, square below, as far down as the
          # divider.
          def band(state)
            left = state.x
            right = left + state.width
            top = state.y
            radius = look(:round_corner, state)
            Svg::Path.new(
              d: band_path(left, right, top, radius),
              fill: look(:background, state),
            )
          end

          def band_path(left, right, top, radius)
            bottom = top + Look::BAR
            "M#{left + radius},#{top} L#{right - radius},#{top} " \
              "A#{radius},#{radius} 0 0 1 #{right},#{top + radius} " \
              "L#{right},#{bottom} L#{left},#{bottom} " \
              "L#{left},#{top + radius} " \
              "A#{radius},#{radius} 0 0 1 #{left + radius},#{top}"
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

          def divider(state)
            bar = state.children.any? ? Look::BAR : Look::LEAF_BAR
            y = state.y + bar
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
