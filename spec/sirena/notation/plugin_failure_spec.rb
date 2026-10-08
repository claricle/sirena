# frozen_string_literal: true

require "spec_helper"

module PluginFailureSpecHelpers
  # A plugin whose `member` reader raises `error`.
  def raising(member, error, id: :raiser)
    FakeNotation::Plugin.new(
      id: id, extensions: %w[.rsr].freeze, prefix: "@#{id}",
    ).tap { |plugin| plugin.define_singleton_method(member) { raise error } }
  end

  def register_with_bad_extensions(error)
    Sirena::Notation.register(raising(:extensions, error))
  end

  def raising_inspect(error)
    Object.new.tap do |odd|
      odd.define_singleton_method(:inspect) { raise error }
    end
  end

  def raising_parse(error)
    FakeNotation::Plugin.new(
      id: :raiser, extensions: [].freeze, prefix: "@raiser",
    ).tap do |plugin|
      plugin.define_singleton_method(:parse) { |_source| raise error }
    end
  end

  # The claims? that picks the notation raises.
  def raising_claims(error)
    Class.new(FakeNotation::Plugin) do
      define_method(:claims?) { |_source| raise error }
    end.new(id: :raiser, extensions: [].freeze, prefix: "@raiser")
  end

  # parse succeeds; the renderer it returns raises when it renders.
  def raising_renderer(error)
    angry = Class.new do
      def initialize(theme:); end

      define_method(:render) { |_graph| raise error }
    end
    raising_parse(nil).tap do |plugin|
      plugin.define_singleton_method(:parse) do |source|
        Sirena::Notation::Parsed.new(
          type: :fake_box, diagram: { source: source },
          transform: FakeNotation::Layout, renderer: angry
        )
      end
    end
  end

  # What Engine#render ends in for an exception raised by a notation: a
  # layer error stays itself, the process's and the host's own unwinding
  # passes, everything else (exhaustion included) is a PipelineError.
  def rendered_as(klass)
    return klass if klass <= Sirena::Error
    return klass if ExceptionFamily.passthrough?(klass) &&
      !(klass <= NoMemoryError)

    Sirena::Engine::PipelineError
  end
end

# Whatever a plugin raises is refused at the boundary, unless it is the
# process's or the host's own. The tables are generated from the loaded
# Exception hierarchy, not from a list of routes someone thought of.
RSpec.describe Sirena::Notation::PluginFailure do
  include PluginFailureSpecHelpers

  include_context "with an isolated notation registry"

  let(:registration_error) { Sirena::NotationRegistrationError }
  let(:pipeline_error) { Sirena::Engine::PipelineError }
  let(:engine) { Sirena::Engine.new }

  it "sees the hierarchy: the roots, the usual, and the four that pass" do
    expect(ExceptionFamily.all)
      .to include(Exception, StandardError, ScriptError, SystemStackError,
                  CGI::InvalidEncoding, *ExceptionFamily::PASSTHROUGH)
  end

  describe ".===" do
    ExceptionFamily.failing.each do |klass|
      it "matches #{klass}" do
        expect(described_class === klass.allocate).to be(true)
      end
    end

    ExceptionFamily.passing.each do |klass|
      it "does not match #{klass}" do
        expect(described_class === klass.allocate).to be(false)
      end
    end

    it "does not match what is not an exception" do
      expect([described_class === Object.new, described_class === nil])
        .to eq([false, false])
    end
  end

  describe "Notation.register" do
    ExceptionFamily.failing.each do |klass|
      it "refuses a getter that raises #{klass}" do
        expect { register_with_bad_extensions(klass.allocate) }
          .to raise_error(registration_error)
      end
    end

    it "names the member whose getter raised a direct Exception" do
      expect { register_with_bad_extensions(CGI::InvalidEncoding) }
        .to raise_error(registration_error,
                        "Notation raiser: extensions is malformed")
    end

    ExceptionFamily.passing.each do |klass|
      it "lets #{klass} from a getter through" do
        expect { register_with_bad_extensions(klass.allocate) }
          .to raise_error(klass)
      end
    end
  end

  describe "Notation.fetch" do
    ExceptionFamily.failing.each do |klass|
      it "names an identifier whose inspect raises #{klass} as uninspectable" do
        expect { Sirena::Notation.fetch(raising_inspect(klass.allocate)) }
          .to raise_error(pipeline_error, /\AInvalid notation: <uninspectable>/)
      end
    end

    ExceptionFamily.passing.each do |klass|
      it "lets #{klass} from an identifier's inspect through" do
        expect { Sirena::Notation.fetch(raising_inspect(klass.allocate)) }
          .to raise_error(klass)
      end
    end
  end

  describe "Engine#render" do
    ExceptionFamily.all.each do |klass|
      it "ends #{klass} from a notation's parse as the contract says" do
        Sirena::Notation.register(raising_parse(klass.allocate))

        expect { engine.render("@raiser body", notation: :raiser) }
          .to raise_error(rendered_as(klass))
      end
    end

    it "wraps a direct Exception from the claims? that picks the notation" do
      Sirena::Notation.register(raising_claims(CGI::InvalidEncoding))

      expect { engine.render("@raiser body") }
        .to raise_error(pipeline_error, /CGI::InvalidEncoding/)
    end

    it "wraps a direct Exception from the renderer a notation returns" do
      Sirena::Notation.register(raising_renderer(CGI::InvalidEncoding))

      expect { engine.render("@raiser body", notation: :raiser) }
        .to raise_error(pipeline_error, /CGI::InvalidEncoding/)
    end
  end
end
