# frozen_string_literal: true

# Differential fuzz harness for Sirena's flowchart node-id grammar.
# Sibling to scripts/sequence_fuzz.rb, sharing its comparison and CLI
# logic via scripts/mermaid_fuzz.rb instead of duplicating it.
#
# Generates random single-node flowchart sources, parses each with
# Sirena's own Parslet grammar, and asks a real, installed mermaid
# (via scripts/mermaid_fuzz_runner.js, driven inside one persistent
# headless-Chrome page) whether it agrees.
#
# Tooling only. Does not ship in the gem, is not required by lib/sirena,
# and is not exercised by `rake`/`rspec`.
#
# Usage:
#   ruby scripts/flowchart_fuzz.rb [--seed N] [--count N] [--verbose]
#
# Exit status: 0 if sirena and mermaid agreed on every case (regression
# corpus included), 1 if any divergence was found, 2 if the regression
# corpus itself failed to reproduce (see mermaid_fuzz.rb).
#
# WHAT THIS GENERATES, AND WHAT IT DOES NOT
#
# Every case has the fixed shape:
#
#   flowchart TD
#       <node-id>
#
# one statement, one line -- a standalone node declaration, the
# narrowest surface `node_id` is used on. The random axis is the node id
# token itself, because PR #21 ("Widen flowchart node ids to what
# mermaid takes") already widened this exact rule once and its own
# comments describe a long, ad hoc list of special cases (dot runs,
# x/o link markers, reserved-word boundaries) -- precisely the shape of
# rule most likely to have a gap fuzzing can find that a fixed example
# list cannot.
#
# Token classes generated for a node id:
#   - "safe" identifier characters: letters, digits, underscore
#   - "wild" characters: - ( ) % @ / \ < > + . | and space -- the same
#     wild pool sequence_fuzz.rb uses for actor names, since both are
#     "an id token embedded in a larger statement grammar" and the same
#     punctuation has caused divergences in both
#   - ids 1-6 characters long, mixing both pools
#
# Token classes this harness does NOT generate, and does not claim to
# cover:
#   - edges, shapes (`[]`, `()`, `{}`, `@{...}`), subgraphs, styling
#     (style/class/classDef/linkStyle), click/href callbacks, comments,
#     multi-statement diagrams, quoted node ids, non-ASCII text
#   - two-node statements (`A-->B`) -- only the single standalone-node
#     statement shape
#
# A clean run says nothing about any of the above; it only says these
# two parsers agree on how to identify a bare, standalone node id.

require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require_relative 'mermaid_fuzz'

module FlowchartFuzz
  # Punctuation drawn from the same rationale as sequence_fuzz.rb's
  # WILD_ACTOR_CHARS: characters a node-id-widening PR has already had to
  # reason about (dash-fusion with an arrow, dot runs, x/o link markers)
  # plus the general "id token embedded in a statement" punctuation set.
  #
  # Deliberately narrower than MermaidFuzz::IdentifierGenerator::DEFAULT_
  # WILD_CHARS -- `~ $ : *` have no stated role in flowchart's own node_id
  # rule (no generic/stereotype/cardinality syntax the way class_diagram
  # and er_diagram have), so this type keeps its own pool rather than the
  # shared default.
  WILD_CHARS = %w[- ( ) % @ / \\ < > + . |].push(' ').freeze

  TEMPLATE = ->(id) { "flowchart TD\n    #{id}\n" }

  # The known divergences this harness is required to catch before its
  # generated numbers are trusted -- see mermaid_fuzz.rb's banner.
  # Reproduced this session against the tip this branch is built on
  # (85acf20, i.e. AFTER PR #21's widening already landed): both were
  # confirmed with `--verbose` runs of this exact generator, seed 42.
  KNOWN_DIVERGENCES = [
    # Sirena's node_id grammar has no rule for a bare "%" -- it is only
    # recognized as the opener of a `%%` comment, which requires a
    # second "%". mermaid accepts a lone "%" as an ordinary node id.
    MermaidFuzz::Case.new('known-1-percent-node-id', "flowchart TD\n    %\n"),
    # The reverse direction: sirena's node_id accepts a trailing
    # "()" run as part of the id ("+F-N()" -> node id "+F-N"), but
    # mermaid's own lexer does not accept unmatched/attached parens
    # there and rejects the whole line.
    MermaidFuzz::Case.new('known-2-trailing-parens-accepted-by-sirena-only', "flowchart TD\n    +F-N()\n"),
  ].freeze

  # Runs Sirena's own FlowchartParser in-process, via MermaidFuzz.safe_parse
  # (see its doc for why unexpected exceptions are caught too, not only
  # ParseError).
  SIRENA_VERDICT_FOR = lambda do |source|
    MermaidFuzz.safe_parse { Sirena::Parser::FlowchartParser.new.parse(source).nodes.map(&:id) }
  end

  RUNNER_KWARGS = {
    label: 'flowchart',
    generator_factory: ->(rng) { MermaidFuzz::IdentifierGenerator.new(rng, wild_chars: WILD_CHARS, template: TEMPLATE) },
    known_divergences: KNOWN_DIVERGENCES,
    sirena_verdict_for: SIRENA_VERDICT_FOR,
    mermaid_getter: 'getVertices',
    mermaid_preflight: "flowchart TD\n    A\n",
  }.freeze
end

MermaidFuzz::CLI.run(ARGV, **FlowchartFuzz::RUNNER_KWARGS) if $PROGRAM_NAME == __FILE__
