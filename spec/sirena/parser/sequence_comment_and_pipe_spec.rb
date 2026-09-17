# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

# Two of the largest classes found by scripts/sequence_fuzz.rb (a
# differential fuzz harness on a sibling branch, not shipped here) against
# mermaid 11.16.1, seed 1, count 10568: 1,456 divergences, all sirena
# rejecting what mermaid accepts. Every row below was run through that same
# real mermaid via the harness's Puppeteer runner during this change.
#
# Class 1 (380 of 1,456): a message line whose first character is a bare
# `%` (not opening `%{`) is a whole-line comment to mermaid, contributing
# zero participants, whatever punctuation follows it.
#
# Class 2 (167 of 1,456): a message endpoint whose first character is `|`
# is ordinary actor-name material to mermaid, kept verbatim including the
# pipe — sirena banned it unconditionally with no arrow-collision reason.
RSpec.describe Sirena::Parser::SequenceParser do
  let(:parser) { described_class.new }

  describe "a bare % at a statement's start is a whole-line comment" do
    it "accepts a comment-only diagram with zero participants" do
      diagram = parser.parse("sequenceDiagram\n    %foo bar->baz: not a message\n")

      expect(diagram.participants).to eq([])
    end

    it "does not swallow the message that follows the comment line" do
      diagram = parser.parse(
        "sequenceDiagram\n    %just a comment\n    Alice->>Bob: hi\n"
      )

      expect(diagram.participants.map(&:id)).to eq(%w[Alice Bob])
    end

    it "does not swallow the comment that follows a message line" do
      diagram = parser.parse(
        "sequenceDiagram\n    Alice->>Bob: hi\n    %trailing comment\n"
      )

      expect(diagram.participants.map(&:id)).to eq(%w[Alice Bob])
    end

    # `comment_statement` does not own every `%`-adjacent case; do not
    # extend it to cover these without re-checking mmdc first: a line
    # starting `%%` also parses to zero participants, but through
    # `common.rb`'s own `ws`/`comment` rule, not this one. `%{x->>A: m`
    # keeps `%{x` as actor material through `mermaid_token_opener`, not
    # through this rule (`str('{').absent?` deliberately excludes it). A
    # bare `%` mid-message still raises, covered by
    # `sequence_actor_names_spec.rb`'s `"A->>%B: m" => nil` row.
  end

  describe "a leading | in a message endpoint is ordinary actor material" do
    it "keeps a leading pipe on the sender, matching mmdc" do
      diagram = parser.parse("sequenceDiagram\n    |foo->>bar: m\n")

      expect(diagram.participants.map(&:id)).to eq(%w[|foo bar])
    end

    it "keeps a leading pipe on the recipient, matching mmdc" do
      diagram = parser.parse("sequenceDiagram\n    foo->>|bar: m\n")

      expect(diagram.participants.map(&:id)).to eq(%w[foo |bar])
    end

    it "keeps a bare pipe recipient after a solid-open arrow, matching mmdc" do
      diagram = parser.parse("sequenceDiagram\n    l-)|: a message\n")

      expect(diagram.participants.map(&:id)).to eq(%w[l |])
    end

    it "keeps a bare pipe recipient after a dotted-open arrow, matching mmdc" do
      diagram = parser.parse("sequenceDiagram\n    l-->|: a message\n")

      expect(diagram.participants.map(&:id)).to eq(%w[l |])
    end
  end
end
