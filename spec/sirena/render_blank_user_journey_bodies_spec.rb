# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena, ".render blank user journey bodies" do
  it "renders blank, whitespace-only, and comment-only bodies" do
    sources = ["journey\n\n", "journey\n  \n", "journey\n  %% comment\n"]
    renders = sources.map { |source| described_class.render(source) }

    expect(renders).to all(start_with("<svg"))
  end
end
