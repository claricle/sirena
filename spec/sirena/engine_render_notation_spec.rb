# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

module EngineRenderNotationHelpers
  def plugin(id, extensions, prefix, klass = FakeNotation::Plugin)
    klass.new(id: id, extensions: extensions.freeze, prefix: prefix)
  end

  def diagram_type_error
    Sirena::Engine::DiagramTypeError
  end

  def pipeline_error
    Sirena::Engine::PipelineError
  end

  def fake_svg(id, text)
    %(<svg data-notation="#{id}">#{text}</svg>)
  end

  def fake_refusal
    "Unable to detect diagram type from source. " \
      "Source must start with one of: @fake"
  end

  def valid_notations
    "Valid notations: fake, mermaid, other"
  end
end

RSpec.describe Sirena::Engine, "#render" do
  include EngineRenderNotationHelpers

  include_context "with an isolated notation registry"

  let(:mermaid_headers) { /Source must start with one of: architecture-beta/ }
  let(:fake_header) { /Source must start with one of: @fake\z/ }

  before do
    Sirena::Notation.register(plugin(:fake, %w[.fake], "@fake"))
    Sirena::Notation.register(plugin(:other, %w[.oth], "@other"))
  end

  describe "a notation added without touching lib" do
    it "renders through Sirena.render when named explicitly" do
      expect(Sirena.render("@fake hello", notation: :fake))
        .to eq(fake_svg(:fake, "@fake hello"))
    end

    it "lets the path extension pick it, though the source is not its own" do
      expect { Sirena.render("hello", path: "x.fake") }
        .to raise_error(diagram_type_error, fake_header)
    end

    it "renders when only the source gives it away (stdin: no path)" do
      expect(Sirena.render("@other body"))
        .to eq(fake_svg(:other, "@other body"))
    end
  end

  describe "precedence" do
    it "takes the explicit notation over a disagreeing path and source" do
      expect { Sirena.render("@other x", path: "x.fake", notation: :mermaid) }
        .to raise_error(diagram_type_error, mermaid_headers)
    end

    it "takes the path extension over a disagreeing source" do
      expect { Sirena.render("@other x", path: "x.fake") }
        .to raise_error(diagram_type_error, fake_header)
    end

    it "uses the engine's notation over what the source looks like" do
      engine = described_class.new(notation: :fake)

      expect { engine.render("graph TD\nA-->B") }
        .to raise_error(diagram_type_error, fake_refusal)
    end

    it "takes the engine's notation over the path extension" do
      engine = described_class.new(notation: :mermaid)

      expect { engine.render("@fake x", path: "x.fake") }
        .to raise_error(diagram_type_error, mermaid_headers)
    end

    it "lets a render's notation override the engine's" do
      engine = described_class.new(notation: :fake)

      expect(engine.render("@other a", notation: "other"))
        .to eq(fake_svg(:other, "@other a"))
    end

    it "keeps mermaid the default for a source nothing claims" do
      expect { described_class.new.render("hello") }
        .to raise_error(diagram_type_error, mermaid_headers)
    end
  end

  describe "a notation chosen without asking its claims?" do
    let(:counting) { plugin(:count, %w[.cnt], "@count", counting_class) }
    let(:counting_class) { FakeNotation::CountingPlugin }

    before { Sirena::Notation.register(counting) }

    it "is not asked when named explicitly" do
      described_class.new.render("anything", notation: :count)

      expect(counting.claims_calls).to eq(0)
    end

    it "is not asked when the path extension picks it" do
      described_class.new.render("anything", path: "x.cnt")

      expect(counting.claims_calls).to eq(0)
    end

    it "is asked once when the source alone decides" do
      described_class.new.render("@count x")

      expect(counting.claims_calls).to eq(1)
    end
  end

  describe "an engine built with a notation" do
    [:fake, "fake"].each do |name|
      it "uses the registry's id for #{name.inspect} when the plugin now " \
         "answers another" do
        Sirena::Notation.fetch(:fake)
          .define_singleton_method(:id) { :changed }
        engine = described_class.new(notation: name)

        expect(engine.render("@fake a")).to eq(fake_svg(:changed, "@fake a"))
      end
    end

    it "normalizes a String subclass through String's own to_sym" do
      notation = Class.new(String) { def to_sym = raise("boom") }.new("fake")
      engine = described_class.new(notation: notation)

      expect(engine.render("@fake a")).to eq(fake_svg(:fake, "@fake a"))
    end
  end

  describe "a notation that cannot read the source" do
    it "raises that notation's own error without a pre-check by the engine" do
      expect { described_class.new.render("graph TD\nA-->B", notation: :fake) }
        .to raise_error(diagram_type_error, fake_refusal)
    end

    [:fake, "fake"].each do |name|
      it "is still the one used when built with #{name.inspect}" do
        engine = described_class.new(notation: name)

        expect { engine.render("graph TD\nA-->B") }
          .to raise_error(diagram_type_error, fake_refusal)
      end
    end
  end

  it "renders from a String path whose to_s is abstract" do
    path = Class.new(String) { def to_s = raise NotImplementedError }
      .new("x.fake")

    expect(described_class.new.render("@fake x", path: path))
      .to eq(fake_svg(:fake, "@fake x"))
  end

  describe "an unknown notation" do
    it "is refused when the engine is built" do
      expect { described_class.new(notation: :nope) }.to raise_error(
        pipeline_error, "Unknown notation: nope. #{valid_notations}"
      )
    end

    it "is refused at render" do
      expect { described_class.new.render("graph TD", notation: "nope") }
        .to raise_error(
          pipeline_error, "Unknown notation: nope. #{valid_notations}"
        )
    end

    it "is refused as an invalid identifier when it is not a Symbol" do
      expect { described_class.new(notation: Object) }.to raise_error(
        pipeline_error,
        "Invalid notation: Object. Notation must be a Symbol or String",
      )
    end

    it "does not treat false as an absent render override" do
      expect { described_class.new.render("graph TD", notation: false) }
        .to raise_error(
          pipeline_error,
          "Invalid notation: false. Notation must be a Symbol or String",
        )
    end

    it "does not treat false as an absent constructor notation" do
      expect { described_class.new(notation: false) }
        .to raise_error(
          pipeline_error,
          "Invalid notation: false. Notation must be a Symbol or String",
        )
    end

    context "with an identifier that is not even an Object" do
      let(:invalid) { BasicObject.new }
      let(:message) do
        "Invalid notation: <uninspectable>. " \
          "Notation must be a Symbol or String"
      end

      it "is refused as the constructor notation" do
        expect { described_class.new(notation: invalid) }
          .to raise_error(pipeline_error, message)
      end

      it "is refused as the render override" do
        expect { described_class.new.render("graph TD", notation: invalid) }
          .to raise_error(pipeline_error, message)
      end
    end

    [
      -> { raise NotImplementedError },
      -> { inspect },
    ].each do |inspection|
      it "refuses a constructor identifier with hostile inspection" do
        invalid = Object.new
        invalid.define_singleton_method(:inspect, &inspection)

        expect { described_class.new(notation: invalid) }
          .to raise_error(pipeline_error, /Invalid notation: <uninspectable>/)
      end

      it "refuses a render identifier with hostile inspection" do
        invalid = Object.new
        invalid.define_singleton_method(:inspect, &inspection)

        expect { described_class.new.render("graph TD", notation: invalid) }
          .to raise_error(pipeline_error, /Invalid notation: <uninspectable>/)
      end
    end

    it "is not wrapped into 'Rendering failed'" do
      expect { described_class.new.render("x", notation: :nope) }
        .to raise_error(pipeline_error, /\AUnknown notation: nope\./)
    end
  end

  describe "verbose logging" do
    let(:log_output) { StringIO.new }
    let(:engine) do
      logger = Logger.new(log_output)
      logger.formatter = proc { |_severity, _time, _name, msg| "#{msg}\n" }
      described_class.new(logger: logger)
    end

    before do
      Sirena::Notation.register(
        plugin(:logging, [], "@log", FakeNotation::LoggingPlugin),
      )
    end

    it "hands the logger to a notation that declares logger:, if verbose" do
      engine.render("@log x", verbose: true)

      expect(log_output.string).to include("fake parse")
    end

    it "hands it nil without verbose" do
      engine.render("@log x", verbose: false)

      expect(log_output.string).to be_empty
    end

    it "still renders a notation that declares no logger: if verbose" do
      engine.render("@fake x", verbose: true)

      expect(log_output.string).to include("Starting render pipeline...")
    end
  end
end
