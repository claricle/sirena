# frozen_string_literal: true

require "fileutils"

# Writes a tiny checkout (Gemfile, lib/sirena.rb and exe/sirena) whose API and CLI
# behaviour is set by keyword, so a spec can seed a difference in one surface.
module FakeSurfaceCheckout
  DEFAULTS = {
    svg_suffix: "", api_error: "boom", cli_out_suffix: "",
    cli_err: "Error: boom", cli_exit: 1
  }.freeze

  def build_fake_checkout(dir, **overrides)
    opts = DEFAULTS.merge(overrides)
    FileUtils.mkdir_p([File.join(dir, "lib"), File.join(dir, "exe")])
    File.write(File.join(dir, "Gemfile"), "# frozen_string_literal: true\n")
    File.write(File.join(dir, "lib", "sirena.rb"), fake_api(opts))
    File.write(File.join(dir, "exe", "sirena"), fake_cli(opts))
    dir
  end

  def fake_api(opts)
    <<~RUBY
      module Sirena
        def self.render(source, _options = {})
          raise ArgumentError, #{opts[:api_error].inspect} if source.include?("bad")

          "<svg>" + source + #{opts[:svg_suffix].inspect} + "</svg>"
        end
      end
    RUBY
  end

  def fake_cli(opts)
    <<~RUBY
      source = File.read(ARGV.fetch(1))
      if source.include?("bad")
        warn #{opts[:cli_err].inspect}
        exit #{opts[:cli_exit]}
      end
      print source, #{opts[:cli_out_suffix].inspect}
    RUBY
  end

  def write_case_file(dir, name, body)
    File.join(dir, name).tap { |path| File.write(path, body) }
  end
end
