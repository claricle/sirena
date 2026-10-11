# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render info validity" do
    ["info diagram", "info unsupported", "info showInfo extra"].each do |src|
      it "refuses #{src.inspect}, as Mermaid's lexer does" do
        expect { described_class.render("#{src}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    ["info", "info showInfo", "info\n  showInfo"].each do |source|
      it "still renders #{source.inspect}" do
        expect(described_class.render("#{source}\n")).to start_with("<svg")
      end
    end
  end
end
