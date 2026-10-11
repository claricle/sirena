# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe "User Journey blank bodies" do
  it "renders blank, whitespace-only, and comment-only bodies" do
    sources = [
      "journey\n\n",
      "journey\n  \n",
      "journey\n  %% comment\n",
    ]

    sources.each do |source|
      expect(Sirena.render(source)).to start_with("<svg")
    end
  end
end
