# frozen_string_literal: true

require "ripper"
require "spec_helper"

RSpec.describe Sirena::Engine do
  let(:engine_path) { File.expand_path("../../../lib/sirena/engine.rb", __dir__) }

  def plantuml_tokens(path)
    comments = %i[on_comment on_embdoc on_embdoc_beg on_embdoc_end]
    Ripper.lex(File.read(path)).filter_map do |(position, type, token)|
      next if comments.include?(type)

      "#{position.first}: #{token}" if token.match?(/plantuml|puml/i)
    end
  end

  it "contains no PlantUML-specific executable token" do
    found = plantuml_tokens(engine_path)
    expect(found).to be_empty, -> { found.join("\n") }
  end
end
