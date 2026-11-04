# frozen_string_literal: true

require "spec_helper"

# Message each parse path raises for a source with an invalid score.
module ScoreMessages
  PATHS = [true, false].freeze

  module_function

  def of(source)
    PATHS.map do |native|
      NativeParity.with_native(native) do
        Sirena::Parser::UserJourney.new.parse(source)
      rescue Sirena::Parser::ScoreError => e
        e.message
      end
    end
  end
end

RSpec.describe Sirena::Parser::Native, ".parse parity (user_journey)" do
  it_behaves_like "native corpus parity", "user_journey"

  it_behaves_like "native edge parity", "user_journey", [
    "journey",
    "journey\n",
    "  journey",
    "Journey\n  A: 3",
    "journey   \n  title T",
    "journey\n  title T\n  section S\n    A: 5: Me, You\n    B: 3\n",
    "journey\n  title  Spaced Title  \n",
    "journey\n  title\n",
    "journey\n  title a: 3\n",
    "journey\n  title a: x\n",
    "journey\n  section\n  A: 1",
    "journey\n  section A\n  section B\n  X: 2: me",
    "journey\r\n  title T\r\n  A: 3: me\r\n",
    "journey\r\n  A: 3\r\n",
    "journey\n  A: 3\n  %% comment\n  B: 4 %% trailing",
    "journey\n  A: 3\n  %% final comment",
    "journey\n  A: 3\n   ",
    "journey\n\n\n  A: 3\n\n",
    "journey\n  A: 3;\n",
    "journey\n  A: 3 : Me, You  \n",
    "journey\n  A: 3:\n  B: 4: \n  C: 5:   \n",
    "journey\n  A: 3: me,\n",
    "journey\n  A: 3: me,,you\n",
    "journey\n  A: 3: , you\n",
    "journey\n  A: 3: a:b, c d\n",
    "journey\n  A: 3: \r\n  B: 4: x, \r\n",
    "journey\n  Café ☕: 4: Zoë, 日本\n",
    "journey\n  A b: 4\n",
    "journey\n  A: 3x\n",
    "journey\n  : 3\n",
    "journey\n  A: 03\n",
    "journey\n  title: 3\n  section: 4\n",
    "journey\n  accTitle: T\n  accDescr: D\n  A: 3",
    "journey\n  ACCTITLE : T\n  AccDescr:D\n",
    "journey\n  accDescr {\n   multi\n   line\n  }\n  A: 3",
    "journey\n  accDescr {\n  %% } comment\n  x\n  }\n  A: 3",
    "journey\n  accDescr {\n  %%{ } }%%\n  x\n  }\n  A: 3",
    "journey\n  accDescr {\n  %%{ } \n  x\n  }\n  A: 3",
    "journey\n  accDescr {\r  %% }\r  x\r  }\n  A: 3",
    "journey\n  accDescr { %% } x }\n  A: 3",
    "journey\n  accDescr {\n unterminated\n  A: 3",
    "journey\n  accDescr { } trailing: 3\n  B: 2",
    "journey\n  accDescr {}\n",
    "journey\n  A: 3\n  accDescr{x}\n  B: 2",
    "%% lead\njourney\n  A: 3",
    "journey\n  A: 3\nsection S\n  B: 2",
    "",
    "   ",
  ]

  [
    "journey\n  A: 0",
    "journey\n  A: 6: me",
    "journey\n  A: 3\n  B: 99",
  ].each do |source|
    it "raises the same ScoreError for #{source.inspect}" do
      skip "parsanol engine absent" unless described_class.available?

      expect(ScoreMessages.of(source)).to eq(
        [ScoreMessages.of(source).first] * 2,
      ).and(all(start_with("Score must be between 1 and 5")))
    end
  end
end
