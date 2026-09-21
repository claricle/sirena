# frozen_string_literal: true

require "ripper"

# Finds every shipped-code reference to svg_conform's `apply_fixes`, which
# rewrites the SVG it is given and so must never run over Sirena's output.
# Reads tokens rather than text, so a comment that mentions the name is not
# a hit but a call, a `send(:apply_fixes)` symbol or a string is.
#
# This finds the literal name only. svg_conform also reaches it without the
# name (`fix: true`, `Fixer`), which the removed-capability spec covers.
module ApplyFixesScan
  SHIPPED_CODE = %r{\A(?:exe/|Rakefile\z|.*\.(?:rb|rake|gemspec)\z)}

  # The gemspec decides what ships; code is the subset a token scan can read.
  def shipped_files(root)
    gemspec = Gem::Specification.load(File.join(root, "sirena.gemspec"))
    gemspec.files.grep(SHIPPED_CODE).map { |f| File.join(root, f) }.select { |f| File.file?(f) }.sort
  end

  def apply_fixes_references(paths)
    paths.flat_map do |path|
      Ripper.lex(File.read(path)).filter_map do |(line, _col), type, text|
        "#{path}:#{line}" if type != :on_comment && text.include?("apply_fixes")
      end
    end
  end
end
