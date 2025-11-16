# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a sequence diagram participant.
    #
    # A participant represents an actor or entity in the sequence diagram
    # that can send and receive messages.
    class SequenceParticipant < Lutaml::Model::Serializable
      # Unique identifier for the participant
      attribute :id, :string

      # Display text/label for the participant
      attribute :label, :string

      # Participant type: :participant, :actor
      attribute :actor_type, :string

      # Initialize with default actor type
      def initialize(*args)
        super
        self.actor_type ||= 'participant'
      end

      # Validates the participant has required attributes.
      #
      # @return [Boolean] true if participant is valid
      def valid?
        !id.nil? && !id.empty? && !label.nil?
      end
    end

    # Represents a sequence diagram message.
    #
    # A message represents communication between participants in a
    # sequence diagram, with various arrow types and optional text.
    class SequenceMessage < Lutaml::Model::Serializable
      # Source participant identifier
      attribute :from_id, :string

      # Target participant identifier
      attribute :to_id, :string

      # Message text content
      attribute :message_text, :string

      # Arrow type: :solid, :dotted, :async, :async_dotted,
      # :solid_cross, :dotted_cross
      attribute :arrow_type, :string

      # Initialize with default arrow type
      def initialize(*args)
        super
        self.arrow_type ||= 'solid'
      end

      # Validates the message has required attributes.
      #
      # @return [Boolean] true if message is valid
      def valid?
        !from_id.nil? && !from_id.empty? &&
          !to_id.nil? && !to_id.empty?
      end
    end

    # Represents an activation box (lifecycle) in a sequence diagram.
    #
    # An activation shows when a participant is active or processing.
    class SequenceActivation < Lutaml::Model::Serializable
      # Participant identifier
      attribute :participant_id, :string

      # Start message index (position in messages array)
      attribute :start_index, :integer

      # End message index (position in messages array)
      attribute :end_index, :integer

      # Validates the activation has required attributes.
      #
      # @return [Boolean] true if activation is valid
      def valid?
        !participant_id.nil? && !participant_id.empty? &&
          !start_index.nil? && !end_index.nil? &&
          start_index <= end_index
      end
    end

    # Represents a note in a sequence diagram.
    #
    # A note provides additional context or information in the diagram.
    class SequenceNote < Lutaml::Model::Serializable
      # Note text content
      attribute :text, :string

      # Position: :left_of, :right_of, :over
      attribute :position, :string

      # Participant identifier(s) - array for :over with multiple
      attribute :participant_ids, :string, collection: true,
                                           default: -> { [] }

      # Message index where the note appears
      attribute :message_index, :integer

      # Validates the note has required attributes.
      #
      # @return [Boolean] true if note is valid
      def valid?
        !text.nil? && !text.empty? &&
          !position.nil? && !participant_ids.empty?
      end
    end

    # Sequence diagram model.
    #
    # Represents a complete sequence diagram with participants, messages,
    # activations, and notes. Sequence diagrams show interactions between
    # participants over time in a vertical timeline format.
    #
    # @example Creating a simple sequence diagram
    #   sequence = Sequence.new
    #   sequence.participants << SequenceParticipant.new(
    #     id: 'Alice',
    #     label: 'Alice',
    #     actor_type: 'actor'
    #   )
    #   sequence.participants << SequenceParticipant.new(
    #     id: 'Bob',
    #     label: 'Bob',
    #     actor_type: 'actor'
    #   )
    #   sequence.messages << SequenceMessage.new(
    #     from_id: 'Alice',
    #     to_id: 'Bob',
    #     message_text: 'Hello Bob',
    #     arrow_type: 'solid'
    #   )
    class Sequence < Base
      # Collection of participants in the sequence diagram
      attribute :participants, SequenceParticipant, collection: true,
                                                    default: -> { [] }

      # Collection of messages between participants
      attribute :messages, SequenceMessage, collection: true,
                                            default: -> { [] }

      # Collection of activation boxes
      attribute :activations, SequenceActivation, collection: true,
                                                  default: -> { [] }

      # Collection of notes
      attribute :notes, SequenceNote, collection: true,
                                      default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :sequence
      def diagram_type
        :sequence
      end

      # Validates the sequence diagram structure.
      #
      # A sequence diagram is valid if:
      # - It has at least one participant
      # - All participants are valid
      # - All messages are valid
      # - All message references point to existing participants
      # - All activations are valid
      # - All notes are valid
      #
      # @return [Boolean] true if sequence diagram is valid
      def valid?
        return false if participants.nil? || participants.empty?
        return false unless participants.all?(&:valid?)
        return false unless messages.nil? || messages.all?(&:valid?)
        return false unless activations.nil? || activations.all?(&:valid?)
        return false unless notes.nil? || notes.all?(&:valid?)

        # Validate message references
        participant_ids = participants.map(&:id)
        messages&.each do |message|
          return false unless participant_ids.include?(message.from_id)
          return false unless participant_ids.include?(message.to_id)
        end

        # Validate activation references
        activations&.each do |activation|
          return false unless participant_ids.include?(
            activation.participant_id
          )
        end

        # Validate note references
        notes&.each do |note|
          note.participant_ids.each do |pid|
            return false unless participant_ids.include?(pid)
          end
        end

        true
      end

      # Finds a participant by its identifier.
      #
      # @param id [String] the participant identifier to find
      # @return [SequenceParticipant, nil] the participant or nil if not
      #   found
      def find_participant(id)
        participants.find { |p| p.id == id }
      end

      # Finds all messages from a specific participant.
      #
      # @param participant_id [String] the source participant identifier
      # @return [Array<SequenceMessage>] messages from the participant
      def messages_from(participant_id)
        messages.select { |m| m.from_id == participant_id }
      end

      # Finds all messages to a specific participant.
      #
      # @param participant_id [String] the target participant identifier
      # @return [Array<SequenceMessage>] messages to the participant
      def messages_to(participant_id)
        messages.select { |m| m.to_id == participant_id }
      end

      # Finds activations for a specific participant.
      #
      # @param participant_id [String] the participant identifier
      # @return [Array<SequenceActivation>] activations for the participant
      def activations_for(participant_id)
        activations.select { |a| a.participant_id == participant_id }
      end
    end
  end
end
