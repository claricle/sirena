# frozen_string_literal: true

require "spec_helper"

# TODO.architecture/01-safety-net.md, Part B step 0. Engine#render used to
# collapse every non-detection failure into one PipelineError, with the
# original backtrace concatenated into the message string. That made the
# corpus harness unable to tell a parse failure from a render failure --
# every one of them read as PipelineError, whatever actually broke.
#
# Each layer now raises its own Sirena::Error subclass and Engine#render
# lets it propagate. PipelineError survives only for a failure with no
# layer of its own.
RSpec.describe Sirena::Engine do
  let(:engine) { described_class.new }

  describe "layer errors are Sirena::Error" do
    it "ParseError is a Sirena::Error" do
      expect(Sirena::Parser::ParseError.ancestors).to include(Sirena::Error)
    end

    it "TransformError is a Sirena::Error" do
      expect(Sirena::Transform::TransformError.ancestors).to include(Sirena::Error)
    end

    it "RenderError is a Sirena::Error" do
      expect(Sirena::Renderer::RenderError.ancestors).to include(Sirena::Error)
    end

    # DiagramTypeError already inherited Sirena::Error before this fix, so
    # it is not pinned here: a stayed-green example proves nothing about
    # this diff. Its unwrapped propagation is already covered by
    # spec/sirena/engine_spec.rb's own DiagramTypeError examples.
  end

  describe "#render propagates a layer's own error" do
    it "raises ParseError, not PipelineError, on a genuine parse failure" do
      # A dangling edge: the grammar reaches end of input mid-statement.
      expect { engine.render("graph TD\nA-->") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "carries no backtrace inside the ParseError message" do
      # The raise_error block form, not a bare rescue: if render stops
      # raising ParseError, `to raise_error` itself fails the example
      # instead of silently passing with the inner expectation never run.
      expect { engine.render("graph TD\nA-->") }
        .to raise_error(Sirena::Parser::ParseError) do |e|
          expect(e.message).not_to match(/\.rb:\d+:in /)
        end
    end

    it "raises TransformError, not PipelineError, when a diagram fails its own validity check" do
      # mmdc renders a bare `graph` header; the flowchart transform refuses
      # it because the model carries no nodes.
      expect { engine.render("graph") }
        .to raise_error(Sirena::Transform::TransformError, "Invalid diagram")
    end

    # DiagramTypeError was already unwrapped before this fix (the old
    # rescue clause named it explicitly), so a fresh example here would
    # stay green against the unfixed code and prove nothing about this
    # diff. spec/sirena/engine_spec.rb already pins that behaviour.
  end

  describe "#render wraps only a failure with no layer of its own" do
    it "wraps it in PipelineError with the class and message, and no backtrace" do
      allow(Sirena::Layout::Fallback).to receive(:apply)
        .and_raise(RuntimeError, "boom")

      expect { engine.render("graph TD\nA-->B\n") }.to raise_error do |error|
        expect(error).to be_a(Sirena::Engine::PipelineError)
        expect(error.message).to eq("Rendering failed: RuntimeError: boom")
      end
    end

    # Cause-chaining (e.cause) is automatic Ruby behaviour for a `raise`
    # executed inside a `rescue` clause -- true whether the message is
    # "boom\n<backtrace>" (old code) or "RuntimeError: boom" (this fix).
    # A pin here would stay green against the unfixed code and prove
    # nothing about this diff.
  end
end
