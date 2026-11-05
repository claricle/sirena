# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"

module Sirena
  module Notation
    module PlantUML
      module Drawing
        # Draws a {Scene}: each mark becomes the element it names.
        class Renderer < Sirena::Renderer::Base
          # @param scene [Scene]
          # @return [Svg::Document]
          def render(scene)
            Svg::Document.new(
              width: scene.width, height: scene.height,
              view_box: scene.view_box
            ).tap do |document|
              scene.marks.each { |mark| document << element(mark) }
            end
          end

          private

          def element(mark)
            mark.element.new.tap do |node|
              mark.attributes.each do |name, value|
                node.public_send(:"#{name}=", value) unless value.nil?
              end
            end
          end
        end
      end
    end
  end
end
