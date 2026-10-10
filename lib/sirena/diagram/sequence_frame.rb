# frozen_string_literal: true

require "lutaml/model"
require_relative "sequence_frame_section"

module Sirena
  module Diagram
    # A control block in a sequence diagram: loop, alt, opt, par, critical,
    # break or rect. It covers the messages whose index is in
    # `start_index...end_index`.
    class SequenceFrame < Lutaml::Model::Serializable
      KINDS = %w[loop alt opt par critical break rect].freeze

      attribute :kind, :string

      # Text after the keyword; the colour for a `rect`
      attribute :label, :string

      # Index of the first message inside the frame
      attribute :start_index, :integer

      # Index of the first message after the frame
      attribute :end_index, :integer

      # Number of frames that enclose this one
      attribute :depth, :integer, default: -> { 0 }

      # Positions of the opening and closing edge among the other frame
      # edges, dividers and notes, in source order
      attribute :open_order, :integer
      attribute :close_order, :integer

      attribute :sections, SequenceFrameSection, collection: true,
                                                 default: -> { [] }
    end
  end
end
