# frozen_string_literal: true

require "yaml"
require_relative "../../scripts/native_types"

# Shared helpers for the native (PARG) / Parslet parity specs. A type's spec
# file calls NativeParity.corpus_examples / edge_examples inside its own
# RSpec.describe; see spec/sirena/parser/native/pie_parity_spec.rb.
module NativeParity
  CORPUS = File.expand_path("../mermaid", __dir__)

  module_function

  def parser_class(directory)
    path, name = NativeTypes::TYPES.fetch(directory)
    require "sirena/parser/#{path}"
    Sirena::Parser.const_get(name)
  end

  def native_directories
    NativeTypes::TYPES.keys.select { |name| parser_class(name).native }
  end

  def fixtures(directory)
    Dir.glob(File.join(CORPUS, directory, "*.mmd"))
  end

  def with_native(native)
    previous = ENV.fetch("SIRENA_NATIVE_PARSER", nil)
    ENV["SIRENA_NATIVE_PARSER"] = native ? "1" : "ruby"
    yield
  ensure
    ENV["SIRENA_NATIVE_PARSER"] = previous
  end

  # [:ok, model yaml] or [:error, message] for one parse path.
  def outcome(directory, source, native:)
    with_native(native) do
      [:ok, dump(directory, parser_class(directory).new.parse(source))]
    end
  rescue Sirena::Parser::ParseError => e
    [:error, e.message]
  end

  # A mindmap node points at its parent, so its YAML dump never ends;
  # the tree is compared as plain data instead.
  def dump(directory, model)
    return model.to_yaml unless directory == "mindmap"

    [model.root && dump_node(model.root), model.nodes.map { dump_node(_1) }]
  end

  def dump_node(node)
    {
      id: node.id, content: node.content, level: node.level,
      shape: node.shape, icon: node.icon, classes: node.classes,
      parent: node.parent&.id, children: node.children.map { dump_node(_1) }
    }
  end

  def same_outcome?(directory, source)
    outcome(directory, source, native: true) ==
      outcome(directory, source, native: false)
  end

  def native_answers(directory)
    with_native(true) do
      fixtures(directory).count do |path|
        Sirena::Parser::Native.parse(parser_class(directory).native.first,
                                     File.read(path))
      end
    end
  end

  def parslet_accepts(directory)
    fixtures(directory).count do |path|
      outcome(directory, File.read(path), native: false).first == :ok
    end
  end
end

# Every corpus fixture of a type: both paths build the same model or fail
# the same way, and the native path answers wherever Parslet accepts.
RSpec.shared_examples "native corpus parity" do |directory|
  it "has fixtures to compare" do
    expect(NativeParity.fixtures(directory)).not_to be_empty
  end

  it "answers natively for every fixture Parslet accepts" do
    skip "parsanol engine absent" unless Sirena::Parser::Native.available?

    expect(NativeParity.native_answers(directory))
      .to be >= NativeParity.parslet_accepts(directory)
  end

  NativeParity.fixtures(directory).each do |path|
    it "agrees with Parslet on #{File.basename(path)}" do
      source = File.read(path)

      expect(NativeParity.outcome(directory, source, native: true))
        .to eq(NativeParity.outcome(directory, source, native: false))
    end
  end
end

# Hand-picked edge inputs: both paths build the same model or fail the
# same way.
RSpec.shared_examples "native edge parity" do |directory, sources|
  sources.each do |source|
    it "agrees on #{source.inspect}" do
      expect(NativeParity.outcome(directory, source, native: true))
        .to eq(NativeParity.outcome(directory, source, native: false))
    end
  end
end
