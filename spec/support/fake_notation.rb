# frozen_string_literal: true

require "sirena"

# A notation written against the public contract alone: no engine, parser or
# layout edit stands behind it. Specs build instances and register them
# inside an isolated registry.
module FakeNotation
  # What a fake notation's transform hands the renderer: a Hash, which
  # Engine#layout_graph passes through untouched.
  class Layout
    def call(diagram, **)
      diagram
    end
  end

  class Document
    attr_reader :xml

    def initialize(xml)
      @xml = xml
    end

    def to_xml
      xml
    end
  end

  class Renderer
    def initialize(theme:); end

    def render(graph)
      Document.new(
        %(<svg data-notation="#{graph[:notation]}">#{graph[:source]}</svg>),
      )
    end
  end

  # Claims sources that start with `prefix`; declares no `logger:` keyword.
  class Plugin
    attr_reader :id, :extensions, :types

    def initialize(id:, extensions:, prefix:, types: [:fake_box])
      @id = id
      @extensions = extensions
      @prefix = prefix
      @types = types
    end

    def claims?(source)
      source.b.start_with?(@prefix)
    end

    def parse(source)
      unless claims?(source)
        raise Sirena::Engine::DiagramTypeError,
              "Unable to detect diagram type from source. " \
              "Source must start with one of: #{@prefix}"
      end

      parsed(source)
    end

    private

    def parsed(source)
      Sirena::Notation::Parsed.new(
        type: types.first,
        diagram: { notation: id, source: source },
        transform: Layout,
        renderer: Renderer,
      )
    end
  end

  # Counts claims? calls and never asks claims? from parse, so a spec can
  # tell who called it.
  class CountingPlugin < Plugin
    attr_reader :claims_calls

    def initialize(**)
      super
      @claims_calls = 0
    end

    def claims?(source)
      @claims_calls += 1
      super
    end

    def parse(source)
      parsed(source)
    end
  end

  # Same as Plugin, but declares `logger:` the way Notation::Mermaid does.
  class LoggingPlugin < Plugin
    def parse(source, logger: nil)
      logger&.debug("fake parse")
      super(source)
    end
  end
end
