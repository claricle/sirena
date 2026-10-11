# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  fixture_dir = "spec/mermaid/class_diagram"
  invalid_cases = {
    "a whitespace-only explicit label" => %w[
      classdiagram_spec-7f7323f5.mmd
      classdiagram_spec-d7130dfa.mmd
      classdiagram_spec-e67f67a1.mmd
      classdiagram_spec-f8d72790.mmd
      should_parse_classes_with_different_text_labels-3b6eef91.mmd
      should_parse_classes_with_different_text_labels-ef4861fc.mmd
    ],
    "an incomplete cssClass statement" => %w[
      classdiagram_styles_spec-945bb347.mmd
      classdiagram_styles_spec-a7127f80.mmd
      classdiagram_styles_spec-bf7e8658.mmd
      classdiagram_styles_spec-cb235322.mmd
      classdiagram_styles_spec-e2427a19.mmd
      should_be_possible_to_apply_a_css_class_to_a_cla-95c9521c.mmd
      should_be_possible_to_apply_a_cssclass_to_a_clas-97fdecbd.mmd
      should_be_possible_to_apply_a_cssclass_to_a_comm-3ba4969f.mmd
      should_be_possible_to_define_and_assign_a_class-74f55631.mmd
      should_properly_assign_multiple_classes_and_styl-b6145455.mmd
    ],
  }

  invalid_cases.each do |category, fixtures|
    fixtures.each do |fixture|
      it "rejects #{category} in #{fixture}" do
        source = File.read(File.join(fixture_dir, fixture))

        expect { described_class.render(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  it "renders nonblank labels with complete cssClass assignments" do
    source = <<~MERMAID
      classDiagram
        class First[" Visible label "]
        class Second
        cssClass "First,Second" highlighted
    MERMAID

    expect(described_class.render(source)).to include("<svg")
  end
end
