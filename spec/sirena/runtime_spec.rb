# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Runtime do
  let(:pie) { "pie\n  \"a\" : 1\n" }
  let(:library) { instance_double(Sirena::Native::Library, render: "<svg>x") }
  let(:pipeline_error) { Sirena::Engine::PipelineError }

  before do
    stub_const("Sirena::Native", Module.new { def self.library; end })
    stub_const("Sirena::Native::Unported", Class.new(StandardError))
    stub_const("Sirena::Native::RenderError", Class.new(StandardError))
    stub_const("Sirena::Native::Library", Class.new { def render(_src); end })
    allow(described_class).to receive(:library).and_return(library)
  end

  around do |example|
    saved = ENV.fetch("SIRENA_RUNTIME", nil)
    ENV.delete("SIRENA_RUNTIME")
    example.run
  ensure
    ENV["SIRENA_RUNTIME"] = saved
  end

  def with_mode(value)
    ENV["SIRENA_RUNTIME"] = value
  end

  def fail_native_with(error, message)
    allow(library).to receive(:render).and_raise(error, message)
  end

  describe ".mode" do
    it "defaults to auto" do
      expect(described_class.mode).to eq("auto")
    end

    it "treats an empty value as auto" do
      with_mode("")
      expect(described_class.mode).to eq("auto")
    end

    %w[auto ruby rust].each do |value|
      it "accepts #{value}" do
        with_mode(value)
        expect(described_class.mode).to eq(value)
      end
    end

    it "rejects an unknown mode" do
      with_mode("jit")
      expect { described_class.mode }
        .to raise_error(ArgumentError, /SIRENA_RUNTIME.*"jit"/)
    end
  end

  describe ".native?" do
    before do
      allow(described_class).to receive(:library).and_call_original
      described_class.reset!
    end

    after { described_class.reset! }

    it "is false when the sirena-native gem cannot be required" do
      allow(described_class).to receive(:require).and_raise(LoadError)

      expect(described_class).not_to be_native
    end

    it "probes once and reuses the answer" do
      allow(described_class).to receive(:require).and_raise(LoadError)
      2.times { described_class.native? }

      expect(described_class).to have_received(:require).once
    end

    it "is true when the gem loads and finds a library" do
      allow(described_class).to receive(:require).and_return(true)
      allow(Sirena::Native).to receive(:library).and_return(library)

      expect(described_class).to be_native
    end
  end

  describe ".render in auto mode" do
    it "answers from the native library" do
      expect(described_class.render(pie, {})).to eq("<svg>x")
    end

    it "leaves renders with options to Ruby" do
      expect(described_class.render(pie, theme: "dark")).to be_nil
    end

    it "does not call the library for renders with options" do
      described_class.render(pie, theme: "dark")

      expect(library).not_to have_received(:render)
    end

    it "leaves a non-Mermaid notation to Ruby" do
      other = instance_double(Sirena::Notation::Mermaid, id: :other)
      allow(Sirena::Notation).to receive(:resolve).and_return(other)

      expect(described_class.render("@startuml\n", {})).to be_nil
    end

    it "falls back when the library reports Unported" do
      fail_native_with(Sirena::Native::Unported, "sankey")

      expect(described_class.render(pie, {})).to be_nil
    end

    it "falls back on a native error so Ruby raises its own class" do
      fail_native_with(Sirena::Native::RenderError, "boom")

      expect(described_class.render(pie, {})).to be_nil
    end

    it "falls back when the source cannot be encoded for the library" do
      fail_native_with(Encoding::UndefinedConversionError, "bad")

      expect(described_class.render(pie, {})).to be_nil
    end

    it "falls back when sirena-native is missing" do
      allow(described_class).to receive(:library).and_return(nil)

      expect(described_class.render(pie, {})).to be_nil
    end
  end

  describe ".render in ruby mode" do
    before { with_mode("ruby") }

    it "renders nothing natively" do
      expect(described_class.render(pie, {})).to be_nil
    end

    it "never touches the library" do
      described_class.render(pie, {})

      expect(library).not_to have_received(:render)
    end
  end

  describe ".render in rust mode" do
    before { with_mode("rust") }

    it "answers from the library" do
      expect(described_class.render(pie, {})).to eq("<svg>x")
    end

    it "raises when the library is missing" do
      allow(described_class).to receive(:library).and_return(nil)

      expect { described_class.render(pie, {}) }
        .to raise_error(pipeline_error, /rust cannot render.*not installed/)
    end

    it "raises on Unported" do
      fail_native_with(Sirena::Native::Unported, "sankey")

      expect { described_class.render(pie, {}) }
        .to raise_error(pipeline_error, /sankey is not ported/)
    end

    it "raises on a native error" do
      fail_native_with(Sirena::Native::RenderError, "boom")

      expect { described_class.render(pie, {}) }
        .to raise_error(pipeline_error, /it failed: boom/)
    end

    it "raises when options rule Rust out" do
      expect { described_class.render(pie, theme: "dark") }
        .to raise_error(pipeline_error, /options or a non-Mermaid/)
    end
  end

  describe "Sirena.render" do
    let(:ruby_svg) do
      with_mode("ruby")
      Sirena.render(pie).tap { ENV.delete("SIRENA_RUNTIME") }
    end

    it "returns the native SVG when the runtime answers" do
      expect(Sirena.render(pie)).to eq("<svg>x")
    end

    it "renders the same bytes in Ruby when the library says Unported" do
      expected = ruby_svg
      fail_native_with(Sirena::Native::Unported, "pie")

      expect(Sirena.render(pie)).to eq(expected)
    end

    it "raises the Ruby exception class when native errors" do
      fail_native_with(Sirena::Native::RenderError, "native says no")

      expect { Sirena.render("") }
        .to raise_error(Sirena::Engine::DiagramTypeError)
    end
  end
end
