# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # A `box` group around the participants declared inside it.
    class SequenceBox < Lutaml::Model::Serializable
      # Fill colour; nil when the box has none
      attribute :color, :string

      attribute :title, :string

      attribute :participant_ids, :string, collection: true,
                                           default: -> { [] }
    end
  end
end
