# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # A `note "text"` or `note for Class "text"` statement of a class
    # diagram.
    class ClassNote < Lutaml::Model::Serializable
      # The note text, without its surrounding quotes
      attribute :text, :string

      # The id of the class the note is attached to; nil for a general note
      attribute :target_id, :string
    end
  end
end
