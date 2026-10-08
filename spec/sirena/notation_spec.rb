# frozen_string_literal: true

require "spec_helper"

module NotationSpecHelpers
  def plugin(id:, extensions: [].freeze, prefix: "@#{id}", **rest)
    FakeNotation::Plugin.new(
      id: id, extensions: extensions, prefix: prefix, **rest,
    )
  end

  def broken(id: :broken, extensions: %w[.brk].freeze, **rest)
    plugin(id: id, extensions: extensions, **rest)
  end

  def resolved(explicit: nil, path: nil, source: "")
    Sirena::Notation.resolve(
      explicit: explicit, path: path, source: source,
    ).id
  end

  def extension_impostor
    Class.new do
      def is_a?(type) = type == String
      def encoding = Encoding::UTF_8
      def valid_encoding? = true
      def match?(_pattern) = true
    end.new
  end
end

RSpec.describe Sirena::Notation do
  include NotationSpecHelpers

  include_context "with an isolated notation registry"

  let(:fake) { plugin(id: :fake, extensions: %w[.fake].freeze) }
  let(:other) { plugin(id: :other, extensions: %w[.oth].freeze) }
  let(:registration_error) { Sirena::NotationRegistrationError }
  let(:pipeline_error) { Sirena::Engine::PipelineError }

  describe ".register" do
    it "returns nil" do
      expect(described_class.register(fake)).to be_nil
    end

    it "accepts ids and extensions with digits, underscores and symbols" do
      odd = plugin(id: :a1, extensions: %w[.c++ .a_1-2].freeze)
      described_class.register(odd)

      expect(described_class.for_extension(".a_1-2")).to equal(odd)
    end

    it "adds notations after the built-in one, in registration order" do
      described_class.register(fake)
      described_class.register(other)

      expect(described_class.ids.map(&:to_s)).to eq(%w[mermaid fake other])
    end

    {
      "an id that is not a Symbol" =>
        [{ id: "fake" }, /id must be a lowercase Symbol/],
      "an id with an uppercase letter" =>
        [{ id: :Fake }, /id must be a lowercase Symbol/],
      "an id starting with a digit" =>
        [{ id: :"1fake" }, /id must be a lowercase Symbol/],
      "an id with a hyphen" =>
        [{ id: :"a-b" }, /id must be a lowercase Symbol/],
      "an id in a non-ASCII-compatible encoding" =>
        [{ id: "a".encode("UTF-16LE").to_sym, prefix: "@" },
         /id must be a lowercase/],
      "an extension with a trailing newline" =>
        [{ extensions: [".brk\n"].freeze }, /frozen Array/],
      "an id with a trailing newline" =>
        [{ id: :"fake\n", prefix: "@" }, /id must be a lowercase Symbol/],
      "extensions that are nil" =>
        [{ extensions: nil }, /frozen Array/],
      "an extension with invalid bytes" =>
        [{ extensions: ["\xff"].freeze }, /frozen Array/],
      "an extension in a non-ASCII-compatible encoding" =>
        [{ extensions: [".a".encode("UTF-16LE")].freeze }, /frozen Array/],
      "types that are nil" =>
        [{ types: nil }, /types must be an Array of Symbols/],
      "extensions that are not frozen" =>
        [{ extensions: %w[.brk] }, /frozen Array/],
      "an extension without a dot" =>
        [{ extensions: %w[brk].freeze }, /frozen Array/],
      "an extension with text before the dot" =>
        [{ extensions: %w[x.brk].freeze }, /frozen Array/],
      "an uppercase extension" =>
        [{ extensions: %w[.BRK].freeze }, /frozen Array/],
      "an extension repeated within the plugin" =>
        [{ extensions: %w[.brk .brk].freeze }, /\.brk is already claimed/],
      "types that are not Symbols" =>
        [{ types: ["box"] }, /types must be an Array of Symbols/],
      "a duplicate id" =>
        [{ id: :mermaid }, /Notation mermaid is already registered/],
      "an extension another notation claims" =>
        [{ extensions: %w[.mmd].freeze }, /extension \.mmd is already claimed/],
    }.each do |label, (overrides, message)|
      it "refuses #{label}" do
        expect { described_class.register(broken(**overrides)) }
          .to raise_error(registration_error, message)
      end
    end

    context "when fake is already registered" do
      before { described_class.register(fake) }

      it "refuses another plugin with its id" do
        expect { described_class.register(plugin(id: :fake)) }
          .to raise_error(registration_error, /Notation fake is already/)
      end

      it "refuses another plugin with its extension" do
        twin = plugin(id: :twin, extensions: %w[.fake].freeze)

        expect { described_class.register(twin) }
          .to raise_error(registration_error, /extension \.fake is already/)
      end
    end

    %w[id extensions types].each do |name|
      {
        "positional" => proc { |_argument| [] },
        "required-keyword" => proc { |argument:| [argument] },
      }.each do |shape, body|
        it "refuses a #{name} that takes a #{shape} argument" do
          bad = broken
          bad.define_singleton_method(name, &body)

          expect { described_class.register(bad) }
            .to raise_error(registration_error, /#{name} must take no arg/)
        end
      end
    end

    %w[claims? parse].each do |name|
      it "refuses a plugin with no #{name}, naming it" do
        incomplete = broken
        incomplete.singleton_class.send(:undef_method, name)

        expect { described_class.register(incomplete) }
          .to raise_error(registration_error, /must respond to #{name}/)
      end
    end

    it "refuses a plugin missing a member, naming it" do
      bare = Object.new
      def bare.id = :bare

      expect { described_class.register(bare) }
        .to raise_error(registration_error, /must respond to extensions/)
    end

    it "refuses a plugin without Object's introspection helpers" do
      expect { described_class.register(BasicObject.new) }
        .to raise_error(registration_error, "Notation must respond to id")
    end

    it "refuses a plugin that lies about the members it has" do
      liar = Object.new
      liar.define_singleton_method(:respond_to?) { |*| true }

      expect { described_class.register(liar) }
        .to raise_error(registration_error, "Notation must respond to id")
    end

    it "refuses a plugin whose respond_to_missing? raises" do
      broken = Object.new
      broken.define_singleton_method(:respond_to_missing?) { |*| raise "boom" }

      expect { described_class.register(broken) }
        .to raise_error(registration_error, "Notation must respond to id")
    end

    boom = -> { raise "boom" }
    abstract = -> { raise NotImplementedError }
    missing_dependency = -> { require "sirena_missing_optional_dependency_42" }
    unparsable = -> { raise SyntaxError, "boom" }
    uninspectable = lambda do
      Object.new.tap { |value| value.define_singleton_method(:inspect, &boom) }
    end
    endless_inspect = lambda do
      Object.new.tap { |v| v.define_singleton_method(:inspect) { inspect } }
    end
    uniterable = -> { Class.new(Array) { def all?(*) = raise("boom") }.new }
    unreadable = lambda do |member|
      lambda do |name|
        raise "boom" if name == member

        Object.instance_method(:method).bind_call(self, name)
      end
    end

    # label => [member reported, method the plugin breaks, its new body]
    {
      "id returns a BasicObject" => [:id, :id, -> { BasicObject.new }],
      "extensions returns a BasicObject" =>
        [:extensions, :extensions, -> { BasicObject.new }],
      "extensions contains a BasicObject" =>
        [:extensions, :extensions, -> { [BasicObject.new].freeze }],
      "types returns a BasicObject" => [:types, :types, -> { BasicObject.new }],
      "id raises" => [:id, :id, boom],
      "extensions raises" => [:extensions, :extensions, boom],
      "types raises" => [:types, :types, boom],
      "id cannot be inspected" => [:id, :id, uninspectable],
      "extensions cannot be inspected" =>
        [:extensions, :extensions, uninspectable],
      "types cannot be inspected" => [:types, :types, uninspectable],
      "types cannot be iterated" => [:types, :types, uniterable],
      "id is an abstract method" => [:id, :id, abstract],
      "types is an abstract method" => [:types, :types, abstract],
      "id requires a missing dependency" => [:id, :id, missing_dependency],
      "extensions requires a missing dependency" =>
        [:extensions, :extensions, missing_dependency],
      "types requires a missing dependency" =>
        [:types, :types, missing_dependency],
      "types has a syntax error" => [:types, :types, unparsable],
      "extensions inspect recurses without end" =>
        [:extensions, :extensions, endless_inspect],
      "method reflection raises" => [:id, :method, ->(_) { raise "boom" }],
      "claims? reflection raises" =>
        [:claims?, :method, unreadable.call(:claims?)],
      "parse reflection raises" => [:parse, :method, unreadable.call(:parse)],
      "public_send raises" => [:id, :public_send, ->(*) { raise "boom" }],
    }.each do |label, (member, broken_method, body)|
      it "refuses a plugin whose #{label}" do
        bad = broken
        bad.define_singleton_method(broken_method, &body)
        who = member == :id ? "Notation" : "Notation broken"

        expect { described_class.register(bad) }
          .to raise_error(registration_error, "#{who}: #{member} is malformed")
      end
    end

    {
      "id" => lambda do
        Object.new.tap do |value|
          value.define_singleton_method(:is_a?) { |type| type == Symbol }
          value.define_singleton_method(:to_s) { "liar" }
        end
      end,
      "extensions" => lambda do
        Object.new.tap do |value|
          value.define_singleton_method(:is_a?) { |type| type == Array }
          value.define_singleton_method(:frozen?) { true }
          value.define_singleton_method(:all?) { true }
          value.define_singleton_method(:find) { nil }
          value.define_singleton_method(:map) { [] }
        end
      end,
      "types" => lambda do
        Object.new.tap do |value|
          value.define_singleton_method(:is_a?) { |type| type == Array }
          value.define_singleton_method(:all?) { |*| true }
        end
      end,
    }.each do |member, impostor|
      it "refuses a #{member} value that lies about its class" do
        bad = broken
        bad.define_singleton_method(member) { impostor.call }

        expect { described_class.register(bad) }
          .to raise_error(registration_error, /#{member}.*(?:must|malformed)/)
      end
    end

    it "stores an extension subclass as a plain String" do
      liar = Class.new(String) { def ==(_other) = true }
      bad = broken(extensions: [liar.new(".lie"), liar.new(".fib")].freeze)
      described_class.register(bad)

      stored = described_class.extensions.last(2)

      expect(stored.map(&:class)).to eq([String, String])
    end

    it "refuses an extension subclass whose match? lies" do
      lying = Class.new(String) { def match?(*) = true }.new("lie").freeze

      expect { described_class.register(broken(extensions: [lying].freeze)) }
        .to raise_error(registration_error, /extensions must be/)
    end

    it "refuses an extension value that lies about its class" do
      impostor = extension_impostor
      bad = broken
      bad.define_singleton_method(:extensions) { [impostor].freeze }

      expect { described_class.register(bad) }
        .to raise_error(registration_error, /extensions must/)
    end

    {
      parse: [:parse, /parse must take one positional argument/],
      claims: [:claims?, /claims\? must take one positional argument/],
    }.each do |label, (name, message)|
      {
        "variadic" => proc { |*| },
        "no-argument" => proc {},
        "two-argument" => proc { |_one, _two| },
        "one-and-splat" => proc { |_one, *| },
        "one-and-optional" => proc { |_one, _two = nil| },
        "required-keyword" => proc { |_one, logger:| },
      }.each do |shape, body|
        it "refuses a #{shape} #{label}" do
          bad = broken
          bad.define_singleton_method(name, &body)

          expect { described_class.register(bad) }
            .to raise_error(registration_error, message)
        end
      end
    end

    it "is a Sirena::Error subclass" do
      expect(registration_error.ancestors).to include(Sirena::Error)
    end

    context "when a plugin with a bad member is refused" do
      before do
        described_class.register(broken(types: ["box"]))
      rescue Sirena::NotationRegistrationError
        nil
      end

      it "records no id" do
        expect(described_class.ids.map(&:to_s)).to eq(%w[mermaid])
      end

      it "records no extension" do
        expect(described_class.extensions).to eq(%w[.mmd])
      end
    end

    it "hands out only frozen extensions" do
      described_class.register(fake)

      expect(described_class.extensions).to all(be_frozen)
    end

    context "when the plugin edits its declared extensions afterwards" do
      let(:edited) { plugin(id: :fake, extensions: [+".fake"].freeze) }

      before do
        described_class.register(edited)
        edited.extensions.first.replace(".changed")
      end

      it "still answers to the extension declared at registration" do
        expect(described_class.for_extension(".fake")).to equal(edited)
      end

      it "does not answer to the edited extension" do
        expect(described_class.for_extension(".changed")).to be_nil
      end
    end
  end

  describe ".fetch" do
    let(:uninspectable_message) do
      "Invalid notation: <uninspectable>. Notation must be a Symbol or String"
    end

    before { described_class.register(fake) }

    it "returns the notation for a Symbol id" do
      expect(described_class.fetch(:fake)).to equal(fake)
    end

    it "returns the notation for a String id" do
      expect(described_class.fetch("fake")).to equal(fake)
    end

    it "uses String conversion for a subclass whose to_sym raises" do
      odd = Class.new(String) { def to_sym = raise("boom") }.new("fake")

      expect(described_class.fetch(odd)).to equal(fake)
    end

    it "does not fold case" do
      expect { described_class.fetch("Fake") }
        .to raise_error(pipeline_error, /\AUnknown notation: Fake\./)
    end

    it "names the given id and every valid one, sorted" do
      described_class.register(other)

      expect { described_class.fetch(:nope) }.to raise_error(
        pipeline_error,
        "Unknown notation: nope. Valid notations: fake, mermaid, other",
      )
    end

    [Object, 3, [:fake], nil].each do |bad|
      it "refuses #{bad.inspect}, which is not a Symbol or String" do
        expect { described_class.fetch(bad) }.to raise_error(
          pipeline_error,
          "Invalid notation: #{bad.inspect}. " \
          "Notation must be a Symbol or String",
        )
      end
    end

    it "refuses an object without Object's inspection helpers" do
      expect { described_class.fetch(BasicObject.new) }
        .to raise_error(pipeline_error, uninspectable_message)
    end

    {
      "raises" => -> { raise "boom" },
      "raises NotImplementedError" => -> { raise NotImplementedError },
      "recurses without end" => -> { inspect },
      "returns a BasicObject" => -> { BasicObject.new },
    }.each do |label, inspection|
      it "refuses an object whose inspect #{label}" do
        odd = Object.new
        odd.define_singleton_method(:inspect, &inspection)

        expect { described_class.fetch(odd) }
          .to raise_error(pipeline_error, uninspectable_message)
      end
    end

    {
      "raises" => lambda do
        Class.new(String) { def to_s = raise("boom") }.new("nope")
      end,
      "raises NotImplementedError" => lambda do
        Class.new(String) do
          def to_s
            raise NotImplementedError
          end
        end.new("nope")
      end,
      "recurses without end" => lambda do
        Class.new(String) { def to_s = to_s }.new("nope")
      end,
      "returns a non-String" => lambda do
        Class.new(String) { def to_s = 7 }.new("nope")
      end,
    }.each do |label, odd|
      it "names an unknown String whose to_s #{label}" do
        expect { described_class.fetch(odd.call) }
          .to raise_error(pipeline_error, /\AUnknown notation: nope\./)
      end
    end

    it "names an object whose inspect is not UTF-8 compatible" do
      odd = Object.new
      odd.define_singleton_method(:inspect) { "odd".encode("UTF-16LE") }

      expect { described_class.fetch(odd) }
        .to raise_error(pipeline_error, /\AInvalid notation: odd\./)
    end

    it "names an object whose inspect String overrides its own encode" do
      text = Class.new(String) { def encode(*) = BasicObject.new }.new("odd")
      odd = Object.new
      odd.define_singleton_method(:inspect) { text }

      expect { described_class.fetch(odd) }
        .to raise_error(pipeline_error, /\AInvalid notation: odd\./)
    end

    it "treats a String subclass whose valid_encoding? raises as unknown" do
      liar = Class.new(String) { def valid_encoding? = raise("boom") }
      odd = liar.new("nope")

      expect { described_class.fetch(odd) }
        .to raise_error(pipeline_error, /\AUnknown notation: nope\./)
    end

    it "names an id in an unconvertible encoding by its bytes" do
      odd = (+"nope").force_encoding("ISO-2022-JP-2")

      expect { described_class.fetch(odd) }
        .to raise_error(pipeline_error, /\AUnknown notation: nope\./)
    end

    [
      "\xff", "\xff".b, "a".encode("UTF-16LE"),
      (+"nope").force_encoding("ISO-2022-JP-2")
    ].each do |odd|
      it "treats #{odd.encoding} #{odd.inspect} as unknown" do
        expect { described_class.fetch(odd) }
          .to raise_error(pipeline_error, /\AUnknown notation:/)
      end
    end
  end

  describe ".resolve" do
    before do
      described_class.register(fake)
      described_class.register(other)
    end

    it "lets the explicit notation beat a hint and a sniff that disagree" do
      id = resolved(explicit: :mermaid, path: "x.fake", source: "@other")

      expect(id).to eq(:mermaid)
    end

    it "lets the extension hint beat the sniff" do
      expect(resolved(path: "x.fake", source: "@other")).to eq(:fake)
    end

    it "sniffs when the extension names no notation" do
      expect(resolved(path: "x.txt", source: "@other")).to eq(:other)
    end

    it "sniffs when there is no path at all (stdin)" do
      expect(resolved(source: "@fake")).to eq(:fake)
    end

    it "falls back to mermaid when nothing claims the source" do
      expect(resolved(path: "x.txt", source: "hello")).to eq(:mermaid)
    end

    it "matches the extension without regard to case" do
      expect(resolved(path: "DIR.FAKE/X.FaKe")).to eq(:fake)
    end

    it "does not take a directory name for an extension" do
      expect(resolved(path: "a.fake/readme", source: "hi")).to eq(:mermaid)
    end

    it "gives a source two notations claim to the one registered first" do
      described_class.register(plugin(id: :twin, prefix: "@fake"))

      expect(resolved(source: "@fake")).to eq(:fake)
    end

    it "does not let a later notation take a source mermaid claims" do
      described_class.register(plugin(id: :greedy, prefix: "graph"))

      expect(resolved(source: "graph TD\nA-->B")).to eq(:mermaid)
    end

    [
      "a.\xff", "bad\xff.fake", "a\0.fake", "\0a.fake",
      ".fake".encode("UTF-16LE"),
      (+"x.fake").force_encoding("ISO-2022-JP-2")
    ].each do |path|
      it "ignores the path #{path.inspect} and sniffs the source" do
        expect(resolved(path: path, source: "@other")).to eq(:other)
      end
    end

    {
      "raises NotImplementedError" => lambda do
        Class.new(String) do
          def to_s
            raise NotImplementedError
          end
        end.new("x.fake")
      end,
      "returns a non-String" => lambda do
        Class.new(String) { def to_s = nil }.new("x.fake")
      end,
    }.each do |label, path|
      it "uses a String path whose to_s #{label} only as a hint" do
        expect(resolved(path: path.call, source: "@other")).to eq(:fake)
      end
    end

    it "raises the unknown-notation error for an unknown explicit id" do
      expect { resolved(explicit: :nope) }
        .to raise_error(pipeline_error, /\AUnknown notation: nope\./)
    end

    it "treats an explicit nil as not given" do
      expect(resolved(explicit: nil, path: "x.fake")).to eq(:fake)
    end

    ["\xff\xfe graph TD".b, "\xc3\x28", "é".encode("ISO-8859-1")].each do |src|
      it "resolves #{src.inspect} to mermaid without raising" do
        expect(resolved(source: src)).to eq(:mermaid)
      end
    end
  end
end
