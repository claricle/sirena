# frozen_string_literal: true

require "spec_helper"

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
  describe "component files, required standalone" do
    %w[sirena/parser sirena/transform sirena/renderer].each do |path|
      it "loads #{path} without first requiring the top-level sirena entry point" do
        out, status = require_standalone(path)

        expect(status).to be_success, "expected exit 0, got #{status.exitstatus}:\n#{out}"
      end
    end
  end
end
