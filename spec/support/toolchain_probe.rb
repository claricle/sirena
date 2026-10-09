# frozen_string_literal: true

require "open3"

# Runs an external tool for the :toolchain specs. A missing binary fails
# in CI and skips on a dev machine.
module ToolchainProbe
  def self.output(*command)
    text, = Open3.capture2e(*command)
    text
  rescue SystemCallError
    nil
  end

  def probe(*command)
    text = ToolchainProbe.output(*command)
    return text if text

    message = "`#{command.join(' ')}` is not installed"
    raise message if ENV["CI"]

    skip "#{message}; install it to run the PlantUML specs locally"
  end
end
