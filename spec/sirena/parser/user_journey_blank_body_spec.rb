# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena, ".render with blank User Journey bodies" do
  it "renders blank, whitespace-only, and comment-only bodies" do
    sources = [
      "journey\n\n",
      "journey\n  \n",
      "journey\n  %% comment\n",
    ]

    sources.each do |source|
      expect(described_class.render(source)).to start_with("<svg")
    end
  end
end
