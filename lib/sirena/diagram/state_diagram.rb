# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a state node in a state diagram.
    #
    # A state node can represent different types of states in a state
    # machine, including normal states, start/end states, choice points,
    # and fork/join nodes.
    class StateNode < Lutaml::Model::Serializable
      # Unique identifier for the state
      attribute :id, :string

      # Display label for the state
      attribute :label, :string

      # State type: :normal, :start, :end, :choice, :fork, :join
      attribute :state_type, :string

      # Optional description for composite states
      attribute :description, :string

      # Child states for composite/nested states
      attribute :children, StateNode, collection: true, default: -> { [] }

      # Initialize with default state type
      def initialize(*args)
        super
        self.state_type ||= 'normal'
      end

      # Validates the state node has required attributes.
      #
      # @return [Boolean] true if state node is valid
      def valid?
        !id.nil? && !id.empty? &&
          !state_type.nil? && !state_type.empty?
      end

      # Checks if this is a start state.
      #
      # @return [Boolean] true if start state
      def start_state?
        state_type == 'start'
      end

      # Checks if this is an end state.
      #
      # @return [Boolean] true if end state
      def end_state?
        state_type == 'end'
      end

      # Checks if this is a choice state.
      #
      # @return [Boolean] true if choice state
      def choice_state?
        state_type == 'choice'
      end

      # Checks if this is a fork state.
      #
      # @return [Boolean] true if fork state
      def fork_state?
        state_type == 'fork'
      end

      # Checks if this is a join state.
      #
      # @return [Boolean] true if join state
      def join_state?
        state_type == 'join'
      end

      # Checks if this is a composite state.
      #
      # @return [Boolean] true if has child states
      def composite_state?
        !children.nil? && !children.empty?
      end
    end

    # Represents a state transition in a state diagram.
    #
    # A transition connects two states with optional trigger event
    # and guard condition.
    class StateTransition < Lutaml::Model::Serializable
      # Source state identifier
      attribute :from_id, :string

      # Target state identifier
      attribute :to_id, :string

      # Optional trigger event for the transition
      attribute :trigger, :string

      # Optional guard condition for the transition
      attribute :guard_condition, :string

      # Validates the transition has required attributes.
      #
      # @return [Boolean] true if transition is valid
      def valid?
        !from_id.nil? && !from_id.empty? &&
          !to_id.nil? && !to_id.empty?
      end

      # Returns the full transition label.
      #
      # @return [String] formatted label with trigger and guard
      def label
        parts = []
        parts << trigger if trigger && !trigger.empty?
        parts << "[#{guard_condition}]" if guard_condition && !guard_condition.empty?
        parts.join(' ')
      end
    end

    # State diagram model.
    #
    # Represents a complete state machine diagram with states and
    # transitions. State diagrams show the dynamic behavior of a
    # system through states, events, and transitions.
    #
    # @example Creating a simple state diagram
    #   diagram = StateDiagram.new(direction: 'TB')
    #   diagram.states << StateNode.new(
    #     id: 'start',
    #     label: '[*]',
    #     state_type: 'start'
    #   )
    #   diagram.states << StateNode.new(
    #     id: 'idle',
    #     label: 'Idle',
    #     state_type: 'normal'
    #   )
    #   diagram.transitions << StateTransition.new(
    #     from_id: 'start',
    #     to_id: 'idle'
    #   )
    class StateDiagram < Base
      # Collection of states in the diagram
      attribute :states, StateNode, collection: true, default: -> { [] }

      # Collection of transitions between states
      attribute :transitions, StateTransition, collection: true,
                                               default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :state_diagram
      def diagram_type
        :state_diagram
      end

      # Validates the state diagram structure.
      #
      # A state diagram is valid if:
      # - It has at least one state
      # - All states are valid
      # - All transitions are valid
      # - All transition references point to existing states
      #
      # @return [Boolean] true if state diagram is valid
      def valid?
        return false if states.nil? || states.empty?
        return false unless states.all?(&:valid?)
        return false unless transitions.nil? ||
                            transitions.all?(&:valid?)

        # Validate transition references
        state_ids = states.map(&:id)
        transitions&.each do |transition|
          return false unless state_ids.include?(transition.from_id)
          return false unless state_ids.include?(transition.to_id)
        end

        true
      end

      # Finds a state by its identifier.
      #
      # @param id [String] the state identifier to find
      # @return [StateNode, nil] the state or nil if not found
      def find_state(id)
        states.find { |s| s.id == id }
      end

      # Finds all transitions originating from a specific state.
      #
      # @param state_id [String] the source state identifier
      # @return [Array<StateTransition>] transitions from the state
      def transitions_from(state_id)
        transitions.select { |t| t.from_id == state_id }
      end

      # Finds all transitions targeting a specific state.
      #
      # @param state_id [String] the target state identifier
      # @return [Array<StateTransition>] transitions to the state
      def transitions_to(state_id)
        transitions.select { |t| t.to_id == state_id }
      end

      # Finds the start state.
      #
      # @return [StateNode, nil] the start state or nil if not found
      def start_state
        states.find(&:start_state?)
      end

      # Finds all end states.
      #
      # @return [Array<StateNode>] end states
      def end_states
        states.select(&:end_state?)
      end

      # Finds all composite states.
      #
      # @return [Array<StateNode>] composite states
      def composite_states
        states.select(&:composite_state?)
      end

      # Finds all choice states.
      #
      # @return [Array<StateNode>] choice states
      def choice_states
        states.select(&:choice_state?)
      end
    end
  end
end
