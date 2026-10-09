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
  COMMAND = /^sirena render .*diagram\.puml.*$/

  Result = Data.define(:status, :stdout, :stderr, :svg)

  module_function

  def readme
    File.read(README)
  end

  def source
    readme.match(SOURCE_BLOCK)[:source]
  end

  def arguments
    Shellwords.split(readme.match(COMMAND)[0]).drop(1)
  end

  def render
    Dir.mktmpdir("sirena-readme-plantuml") do |dir|
      File.write(File.join(dir, "diagram.puml"), source)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I", LIB, EXECUTABLE, *arguments, chdir: dir
      )
      svg = File.binread(File.join(dir, "output.svg")) if status.success?
      Result.new(status:, stdout:, stderr:, svg:)
    end
  end
end

RSpec.describe PlantUmlReadmeExample do
  it "uses the supported CLI notation-loading path to render valid SVG" do
    result = PlantUmlReadmeExample.render
    document = REXML::Document.new(result.svg)
    text = document.get_elements("//text").map(&:text)
    facts = [
      result.status.success?,
      result.stdout,
      result.stderr,
      document.root.name,
      text.grep(/User|Account|owns/).sort,
    ]

    expect(facts).to eq(
      [true, "", "", "svg", %w[Account User owns]],
    )
  end
end
