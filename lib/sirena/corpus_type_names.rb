# frozen_string_literal: true

module Sirena
  # The one table relating spec/mermaid directory names to the type symbols
  # in {Sirena::Notation::Mermaid::TYPES}. A directory with no registered
  # type (diagrams that must fail detection) maps to nil.
  #
  # Read by {Sirena::DiagramRegistry.corpus_directories} and by
  # Sirena::Corpus.registry_type in tasks/corpus.rake. One directory names
  # each type.
  module CorpusTypeNames
    DIRECTORIES = {
      "architecture" => :architecture,
      "block" => :block,
      "c4" => :c4,
      "class_diagram" => :class_diagram,
      "er_diagram" => :er_diagram,
      "error" => :error,
      "flowchart" => :flowchart,
      "gantt" => :gantt,
      "gitgraph" => :git_graph,
      "info" => :info,
      "kanban" => :kanban,
      "mindmap" => :mindmap,
      "packet" => :packet,
      "pie" => :pie,
      "quadrant" => :quadrant,
      "radar" => :radar,
      "requirement" => :requirement,
      "sankey" => :sankey,
      "sequence" => :sequence,
      "state_diagram" => :state_diagram,
      "timeline" => :timeline,
      "treemap" => :treemap,
      "unknown" => nil,
      "user_journey" => :user_journey,
      "xychart" => :xychart,
    }.freeze

    class << self
      # @return [Symbol, nil] the registry type for a corpus directory
      def registry_type(directory)
        DIRECTORIES[directory]
      end

      # @return [Array<String>] corpus directories holding a registry type
      def directories_for(type)
        DIRECTORIES.select { |_, name| name == type }.keys
      end
    end
  end
end
