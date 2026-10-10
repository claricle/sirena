# frozen_string_literal: true

module SequenceActorNamesHelpers
  EXTRACTORS = {
    participants: ->(diagram) { diagram.participants.map(&:id) },
    labels: ->(diagram) { diagram.participants.map(&:label) },
    activations: lambda do |diagram|
      diagram.activations.map do |activation|
        [
          activation.participant_id,
          activation.start_index,
          activation.end_index,
        ]
      end
    end,
    message_routes: lambda do |diagram|
      diagram.messages.map { |message| [message.from_id, message.to_id] }
    end,
    message_details: lambda do |diagram|
      diagram.messages.map do |message|
        [message.from_id, message.to_id, message.message_text]
      end
    end,
    message_texts: ->(diagram) { diagram.messages.map(&:message_text) },
  }.freeze

  def ids_for(case_name)
    parser.parse(File.read(sequence_fixture(case_name))).participants.map(&:id)
  end

  def sequence_fixture(case_name)
    File.expand_path("../mermaid/sequence/#{case_name}.mmd", __dir__)
  end

  def multiline_labels
    [
      "multiline<br>text", "multiline<br/>text",
      "multiline<br />text", "multiline<br \\t/>text"
    ]
  end

  def expected_route(source_id, target_id)
    {
      participants: [source_id, target_id],
      message_routes: [[source_id, target_id]],
    }
  end

  def expect_sequence(diagram, expected)
    actual = expected.to_h do |key, _value|
      [key, EXTRACTORS.fetch(key).call(diagram)]
    end
    expect(actual).to eq(expected)
  end

  private_constant :EXTRACTORS
end
