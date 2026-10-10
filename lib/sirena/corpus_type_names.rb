# frozen_string_literal: true

module Sirena
  # The one table relating spec/mermaid directory names to the type symbols
  # in {Sirena::Notation::Mermaid::TYPES}. A directory with no registered
  # type (diagrams that must fail detection) maps to nil.
  #
  # Read by {Sirena::DiagramRegistry.corpus_directories} and by
  # Sirena::Corpus.registry_type in tasks/corpus.rake. Several directories
  # may name one type until the duplicate directories are merged.
  module CorpusTypeNames
    DIRECTORIES = {
      "architecture" => :architecture,
      "block" => :block,
      "c4" => :c4,
      "class" => :class_diagram,
      "class_diagram" => :class_diagram,
      "er" => :er_diagram,
      "er_diagram" => :er_diagram,
      "error" => :error,
      "flowchart" => :flowchart,
      "gantt" => :gantt,
      "git" => :git_graph,
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
      "state" => :state_diagram,
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
