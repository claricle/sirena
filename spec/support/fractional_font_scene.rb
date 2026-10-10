# frozen_string_literal: true

# Widens every label font size in a layout scene by half a point on its
# way into a renderer, so renderer code that formats a non-integer font
# size runs. Layouts emit whole-number sizes today; the scene is the
# renderer's public input, so a fractional size is a valid scene.
module FractionalFontScene
  module_function

  # Prepend to a renderer instance's singleton class.
  module Widening
    def render(scene)
      super(FractionalFontScene.widen(scene))
    end
  end

  def widen(object)
    case object
    when Array then object.each { |item| widen(item) }
    when Lutaml::Model::Serializable then widen_attributes(object)
    end
    object
  end

  def widen_attributes(model)
    model.class.attributes.each_key do |name|
      value = model.public_send(name)
      if name == :font_size && value
        model.public_send(:"#{name}=", value + 0.5)
      else
        widen(value)
      end
    end
  end
end
