# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # One `else`, `and` or `option` divider inside a sequence frame.
    class SequenceFrameSection < Lutaml::Model::Serializable
      # Divider keyword: else, and or option
      attribute :kind, :string

      # Text after the keyword
      attribute :label, :string

      # Index of the first message that follows the divider
      attribute :start_index, :integer

      # Position of the divider among the frame edges and notes, in
      # source order
      attribute :order, :integer
    end
  end
end
