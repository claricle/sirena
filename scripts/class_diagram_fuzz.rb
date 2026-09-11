# frozen_string_literal: true

# Differential fuzz harness for Sirena's class-diagram identifier
# grammar. Sibling to scripts/sequence_fuzz.rb, sharing its comparison
# and CLI logic via scripts/mermaid_fuzz.rb instead of duplicating it.
#
# Generates random single-class classDiagram sources, parses each with
# Sirena's own Parslet grammar, and asks a real, installed mermaid
# (via scripts/mermaid_fuzz_runner.js, driven inside one persistent
# headless-Chrome page) whether it agrees.
#
# Tooling only. Does not ship in the gem, is not required by lib/sirena,
# and is not exercised by `rake`/`rspec`.
#
# Usage:
#   ruby scripts/class_diagram_fuzz.rb [--seed N] [--count N] [--verbose]
#
# Exit status: 0 if sirena and mermaid agreed on every case (regression
# corpus included), 1 if any divergence was found, 2 if the regression
# corpus itself failed to reproduce (see mermaid_fuzz.rb).
#
# WHAT THIS GENERATES, AND WHAT IT DOES NOT
#
# Every case has the fixed shape:
#
#   classDiagram
#       <class-name>
#
# one statement, one line -- the grammar's `standalone_class` rule: a
# bare class name with no `class` keyword, no body, no relationship.
# The random axis is the class name token, mirroring how
# sequence_fuzz.rb and flowchart_fuzz.rb each fuzz their own type's
# bare-identifier statement.
#
# Token classes generated for a class name:
#   - "safe" identifier characters: letters, digits, underscore
#   - "wild" characters: - ( ) % @ / \ < > + . | ~ $ : * and space --
#     `~` and `<`/`>` are each individually drawn (never composed as the
#     two-character `<<...>>` stereotype delimiter this harness does not
#     construct) because they participate in mermaid's real class-diagram
#     syntax (generics, stereotypes), so they are included even though
#     sirena's class_name rule (`[a-zA-Z_][a-zA-Z0-9_.]*`) does not expect
#     them outside those constructs
#   - names 1-6 characters long, mixing both pools
#
# Token classes this harness does NOT generate, and does not claim to
# cover:
#   - `class Name { ... }` declarations, attributes, methods,
#     relationships, namespaces, stereotypes, generics, notes, click
#     callbacks, multi-statement diagrams, quoted names, non-ASCII text
#
# A clean run says nothing about any of the above; it only says these
# two parsers agree on how to identify a bare, standalone class name --
# and, per the KNOWN_DIVERGENCES below, they currently do not.

require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require_relative 'mermaid_fuzz'

module ClassDiagramFuzz
  # `~` and `<<>>` participate in mermaid's real class-diagram syntax
  # (generics, stereotypes), which is why this type wants them even
  # though sirena's class_name rule (`[a-zA-Z_][a-zA-Z0-9_.]*`) does not
  # expect them outside those constructs. They are already part of the
  # shared default pool, so no override is needed here.
  WILD_CHARS = MermaidFuzz::IdentifierGenerator::DEFAULT_WILD_CHARS
  TEMPLATE = ->(id) { "classDiagram\n    #{id}\n" }

  # The known divergences this harness is required to catch before its
  # generated numbers are trusted -- see mermaid_fuzz.rb's banner.
  # Reproduced this session, both confirmed with `--verbose` runs of
  # this exact generator (seed 42) AND, for the first, independently
  # against a real `mmdc` SVG render (the letter "K" does not appear
  # anywhere in the rendered output).
  KNOWN_DIVERGENCES = [
    # Sirena's `standalone_class` rule registers a class for ANY bare
    # identifier line, including a single safe letter. Real mermaid
    # silently drops a bare identifier line with no `class` keyword and
    # registers no class at all -- getClasses() comes back empty, and
    # the class does not appear in a real rendered SVG either. This is
    # not a punctuation edge case: it reproduces on ordinary letters
    # ("K", "q", "h", ...), so it is a systemic difference in what
    # counts as a class declaration, not a lexer gap.
    MermaidFuzz::Case.new('known-1-bare-identifier-not-a-class-in-mermaid', "classDiagram\n    K\n"),
    # A bare "-" is likewise silently accepted (and dropped) by mermaid,
    # while sirena's class_name rule (which requires a leading
    # `[a-zA-Z_]`) rejects the line outright.
    MermaidFuzz::Case.new('known-2-dash-rejected-by-sirena-only', "classDiagram\n    -\n"),
  ].freeze

  # Runs Sirena's own ClassDiagramParser in-process, via
  # MermaidFuzz.safe_parse (see its doc for why unexpected exceptions are
  # caught too, not only ParseError).
  SIRENA_VERDICT_FOR = lambda do |source|
    MermaidFuzz.safe_parse { Sirena::Parser::ClassDiagramParser.new.parse(source).entities.map(&:id) }
  end

  RUNNER_KWARGS = {
    label: 'class_diagram',
    generator_factory: ->(rng) { MermaidFuzz::IdentifierGenerator.new(rng, wild_chars: WILD_CHARS, template: TEMPLATE) },
    known_divergences: KNOWN_DIVERGENCES,
    sirena_verdict_for: SIRENA_VERDICT_FOR,
    mermaid_getter: 'getClasses',
    mermaid_preflight: "classDiagram\n    class A\n",
  }.freeze
end

MermaidFuzz::CLI.run(ARGV, **ClassDiagramFuzz::RUNNER_KWARGS) if $PROGRAM_NAME == __FILE__
