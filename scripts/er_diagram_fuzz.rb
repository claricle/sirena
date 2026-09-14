# frozen_string_literal: true

# Differential fuzz harness for Sirena's ER-diagram identifier grammar.
# Sibling to scripts/sequence_fuzz.rb, sharing its comparison and CLI
# logic via scripts/mermaid_fuzz.rb instead of duplicating it.
#
# Generates random single-entity erDiagram sources, parses each with
# Sirena's own Parslet grammar, and asks a real, installed mermaid
# (via scripts/mermaid_fuzz_runner.js, driven inside one persistent
# headless-Chrome page) whether it agrees.
#
# Tooling only. Does not ship in the gem, is not required by lib/sirena,
# and is not exercised by `rake`/`rspec`.
#
# Usage:
#   ruby scripts/er_diagram_fuzz.rb [--seed N] [--count N] [--verbose]
#
# Exit status: 0 if sirena and mermaid agreed on every case (regression
# corpus included), 1 if any divergence was found, 2 if the regression
# corpus itself failed to reproduce (see mermaid_fuzz.rb).
#
# WHAT THIS GENERATES, AND WHAT IT DOES NOT
#
# Every case has the fixed shape:
#
#   erDiagram
#       <entity-id>
#
# one statement, one line -- the grammar's `entity_declaration` rule.
# The random axis is the entity id token. Sirena's entity id is the
# common `identifier` rule (`[a-zA-Z_][a-zA-Z0-9_]*`), the same narrow
# rule already widened for flowchart and kanban node ids (PRs #21, #27)
# and shown to be wrong for state ids by state_diagram_fuzz.rb.
#
# Token classes generated for an entity id:
#   - "safe" identifier characters: letters, digits, underscore
#   - "wild" characters: - ( ) % @ / \ < > + . | ~ $ : * and space
#   - ids 1-6 characters long, mixing both pools
#
# Token classes this harness does NOT generate, and does not claim to
# cover:
#   - entity attribute blocks (`{ ... }`), relationships and their
#     cardinality notation, relationship labels, multi-statement
#     diagrams, quoted entity names, non-ASCII text
#
# A clean run says nothing about any of the above; it only says these
# two parsers agree on how to identify a bare, standalone entity id --
# and, per the KNOWN_DIVERGENCES below, they currently do not.

require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require_relative 'mermaid_fuzz'

module ErDiagramFuzz
  WILD_CHARS = MermaidFuzz::IdentifierGenerator::DEFAULT_WILD_CHARS
  TEMPLATE = ->(id) { "erDiagram\n    #{id}\n" }

  # The known divergence this harness is required to catch before its
  # generated numbers are trusted -- see mermaid_fuzz.rb's banner.
  # Reproduced this session with a `--verbose` run of this exact
  # generator, seed 42.
  KNOWN_DIVERGENCES = [
    # Sirena's entity id, via the common `identifier` rule, cannot lead
    # with a digit. mermaid accepts a bare "1" as an entity id.
    MermaidFuzz::Case.new('known-1-digit-leading-entity-id', "erDiagram\n    1\n"),
  ].freeze

  # Runs Sirena's own ErDiagramParser in-process, via MermaidFuzz.safe_parse
  # (see its doc for why unexpected exceptions are caught too, not only
  # ParseError).
  SIRENA_VERDICT_FOR = lambda do |source|
    MermaidFuzz.safe_parse { Sirena::Parser::ErDiagramParser.new.parse(source).entities.map(&:id) }
  end

  RUNNER_KWARGS = {
    label: 'er_diagram',
    generator_factory: ->(rng) { MermaidFuzz::IdentifierGenerator.new(rng, wild_chars: WILD_CHARS, template: TEMPLATE) },
    known_divergences: KNOWN_DIVERGENCES,
    sirena_verdict_for: SIRENA_VERDICT_FOR,
    mermaid_getter: 'getEntities',
    mermaid_preflight: "erDiagram\n    A\n",
  }.freeze
end

MermaidFuzz::CLI.run(ARGV, **ErDiagramFuzz::RUNNER_KWARGS) if $PROGRAM_NAME == __FILE__
