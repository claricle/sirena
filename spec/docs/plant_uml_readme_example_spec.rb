# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "rexml/document"
require "shellwords"
require "tmpdir"

module PlantUmlReadmeExample
  ROOT = File.expand_path("../..", __dir__)
  README = File.join(ROOT, "README.adoc")
  EXECUTABLE = File.join(ROOT, "exe/sirena")
  LIB = File.join(ROOT, "lib")
  SOURCE_BLOCK = /\n----\n(?<source>@startuml\n.*?@enduml)\n----/m

  Result = Data.define(:status, :stdout, :stderr, :svg)

  module_function

  def readme
    File.read(README)
  end

  def source(name)
    sources = readme.scan(SOURCE_BLOCK).flatten
    sources.fetch(name == "diagram" ? 0 : 1)
  end

  def arguments(name)
    command = /^sirena render .*#{name}\.puml.*$/
    Shellwords.split(readme.match(command)[0]).drop(1)
  end

  def render(name)
    Dir.mktmpdir("sirena-readme-plantuml") do |dir|
      File.write(File.join(dir, "#{name}.puml"), source(name))
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I", LIB, EXECUTABLE, *arguments(name), chdir: dir
      )
      svg = File.binread(output(dir, name)) if status.success?
      Result.new(status:, stdout:, stderr:, svg:)
    end
  end

  def output(dir, name)
    File.join(dir, name == "diagram" ? "output.svg" : "#{name}.svg")
  end

  def facts(result, pattern)
    document = REXML::Document.new(result.svg)
    text = document.get_elements("//text").map(&:text)
    [result.status.success?, result.stdout, result.stderr,
     document.root.name, text.grep(pattern).sort]
  end
end

RSpec.describe PlantUmlReadmeExample do
  it "renders the class example through the CLI notation-loading path" do
    result = described_class.render("diagram")
    expect(described_class.facts(result, /User|Account|owns/)).to eq(
      [true, "", "", "svg", %w[Account User owns]],
    )
  end

  it "renders the sequence example through the same path" do
    result = described_class.render("sequence")
    expect(described_class.facts(result, /Alice|Bob|hello|hi/)).to eq(
      [true, "", "", "svg", %w[Alice Alice Bob Bob hello hi]],
    )
  end
end
