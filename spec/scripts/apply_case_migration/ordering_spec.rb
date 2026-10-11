# frozen_string_literal: true

require "spec_helper"
require "json"
require "yaml"
require_relative "../../../scripts/apply_case_migration"

RSpec.describe ApplyCaseMigration::Ordering do
  let(:rows) { [{ "case" => "pie/b.mmd" }, { "case" => "pie/z.mmd" }] }
  let(:renamed) { [{ "case" => "pie/z.mmd" }, { "case" => "pie/b.mmd" }] }

  def crlf(text) = text.gsub("\n", "\r\n").b

  def json(data) = "#{JSON.pretty_generate(data)}\n"

  it "sorts a CRLF JSON file and keeps its CRLF line endings" do
    text, kind = described_class.call(
      "s.json", crlf(json(rows)), crlf(json(renamed))
    )
    expect([kind, text]).to eq([:structured, crlf(json(rows))])
  end

  it "sorts a CRLF YAML file and keeps its CRLF line endings" do
    text, kind = described_class.call(
      "v.yml", crlf(YAML.dump(rows)), crlf(YAML.dump(renamed))
    )
    expect([kind, text]).to eq([:structured, crlf(YAML.dump(rows))])
  end

  it "still sorts an LF file in LF" do
    text, kind = described_class.call("s.json", json(rows).b, json(renamed))
    expect([kind, text]).to eq([:structured, json(rows)])
  end

  it "leaves a file with mixed line endings unverified" do
    mixed = json(rows).sub("\n", "\r\n").b
    expect(described_class.call("s.json", mixed, json(renamed)).last)
      .to eq(:unverified)
  end
end
