# frozen_string_literal: true

require "spec_helper"
require "open3"

# TODO.architecture/01-safety-net.md, Part B step 0. Each pipeline layer's
# own Error class inherits Sirena::Error so
# Engine#render can propagate it unwrapped. That constant used to be
# defined only inline inside lib/sirena.rb's own require chain, so a
# process that requires a component file directly -- "sirena/parser",
# "sirena/transform", or "sirena/renderer" -- without first requiring the
# top-level "sirena" never saw Sirena::Error defined, and blew up with
# `NameError: uninitialized constant Sirena::Error` the moment the
# component's base.rb loaded. Nothing in this repo's own suite exercised
# that path (spec_helper always requires "sirena" first), so the failure
# was invisible until it was probed directly. Sirena::Error now lives in
# its own file (lib/sirena/error.rb, following the version.rb pattern) and
# each base.rb require_relative's it directly.
#
# Each example shells out to a real subprocess, not an in-process require
# -- $LOADED_FEATURES would make a second `require "sirena/parser"` in
# this same process a silent no-op once spec_helper has already loaded the
# whole gem.
RSpec.describe Sirena do
  # Scoped to this example group, not a top-level `def` -- matches the
  # `def renders?` pattern in flowchart_semicolon_spec.rb rather than
  # leaking a helper onto Object.
  def require_standalone(path)
    Open3.capture2e("ruby", "-Ilib", "-e", "require #{path.inspect}")
  end

  describe "component files, required standalone" do
    %w[sirena/parser sirena/transform sirena/renderer sirena/engine].each do |path|
      it "loads #{path} without first requiring the top-level sirena entry point" do
        out, status = require_standalone(path)

        expect(status).to be_success, "expected exit 0, got #{status.exitstatus}:\n#{out}"
      end
    end

    # A bare "loads without raising" assertion is vacuous specifically for
    # engine.rb: DiagramTypeError/PipelineError are referenced only inside
    # method bodies, so a subprocess still exits 0 even with both error
    # requires deleted (proven by executing that exact mutation). This
    # gap is unique to engine.rb among the four components -- parser,
    # transform and renderer already had this same guarantee at the base
    # tip (their nested Error classes were defined directly under the
    # `require_relative '../error'` already present in each base.rb, so
    # the guarantee predates this diff and needs no new example here).
    it "defines DiagramTypeError and PipelineError as Sirena::Error subclasses when sirena/engine is required standalone" do
      out, status = Open3.capture2e(
        "ruby", "-Ilib", "-e",
        'require "sirena/engine"; ' \
        'puts Sirena::Engine::DiagramTypeError < Sirena::Error; ' \
        'puts Sirena::Engine::PipelineError < Sirena::Error'
      )

      expect(status).to be_success, "expected exit 0, got #{status.exitstatus}:\n#{out}"
      expect(out.lines.map(&:chomp)).to eq(%w[true true])
    end
  end
end
