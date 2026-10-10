# frozen_string_literal: true

# Walks an emitted IR tree and collects the strings that name a construct.
module IrWalk
  VOCABULARY_FIELDS = %i[role dimension source_marker target_marker].freeze

  def ir_models(root)
    return [] unless root.is_a?(Sirena::IR::Model)

    children = root.class.attributes.keys.flat_map do |name|
      Array(root.public_send(name)).flat_map { |value| ir_models(value) }
    end
    [root] + children
  end

  def ir_vocabulary(root)
    ir_models(root).flat_map do |model|
      VOCABULARY_FIELDS.filter_map do |field|
        model.public_send(field) if model.respond_to?(field)
      end
    end
  end
end

RSpec.configure { |config| config.include IrWalk }
