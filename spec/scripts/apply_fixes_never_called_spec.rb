# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
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

  # Number of references in a source string, written to a file so the scan
  # runs the same path it runs over shipped files.
  def apply_fixes_reference_count(source)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "seeded.rb")
      File.write(path, source)
      apply_fixes_references([path]).size
    end
  end
end

RSpec.describe "svg_conform apply_fixes", type: :task do
  include ApplyFixesScan

  let(:repo_root) { File.expand_path("../..", __dir__) }

  it "is referenced nowhere in shipped code" do
    expect(apply_fixes_references(shipped_files(repo_root))).to be_empty
  end

  # scripts/, the Rakefile and the gemspec are dev-only: D6 (sirena.gemspec's
  # `files` became a lib+exe allowlist) means none of them ship, so they are
  # not in the population this scan reads and have no row here. D8 moved
  # every .rake file out of lib/ entirely (lib/tasks -> tasks/), so no
  # shipped lib .rake file exists any more either -- no row for it.
  {
    "lib ruby" => %r{/lib/.*\.rb\z},
    "exe" => %r{/exe/[^/]+\z}
  }.each do |label, pattern|
    it "scans at least one shipped #{label} file" do
      expect(shipped_files(repo_root).grep(pattern)).not_to be_empty
    end
  end

  describe "the capability itself" do
    # Removed rather than watched: every svg_conform entry point that rewrites
    # a document raises, so a call by any spelling (`fix: true`, Fixer, send)
    # fails here instead of hiding from the token scan.
    let(:fixes_called) { Class.new(StandardError) }
    let(:profile) { Sirena::Svg::CONFORMANCE_PROFILE }
    let(:conformant_svgs) do
      %w[flowchart sequence class_diagram state_diagram er_diagram user_journey xy_chart sankey].map do |type|
        Sirena::Engine.new.render(File.read(File.join(repo_root, "spec", "fixtures", type, "input.mmd")))
      end
    end

    before do
      require "svg_conform"
      { SvgConform::ValidationResult => [:apply_fixes],
        SvgConform::Fixer => [:apply_fix, :apply_fixes, :apply_validation_fixes],
        SvgConform::Profile => [:apply_remediations],
        SvgConform::RemediationEngine => [:apply_remediations] }.each do |klass, names|
        names.each { |name| allow_any_instance_of(klass).to receive(name).and_raise(fixes_called) } # rubocop:disable RSpec/AnyInstance
      end
    end

    it "is not reached when fix: true validates Sirena output, as a string or a file" do
      Dir.mktmpdir do |dir|
        conformant_svgs.each_with_index do |svg, i|
          path = File.join(dir, "#{i}.svg")
          File.write(path, svg)

          expect(SvgConform.validate(svg, profile: profile, fix: true)).to be_valid
          expect(SvgConform.validate_file(path, profile: profile, fix: true)).to be_valid
        end
      end
    end

    it "raises when a fixable violation reaches it, so the trap is live" do
      allow_any_instance_of(SvgConform::ValidationResult).to receive(:fixable?).and_return(true) # rubocop:disable RSpec/AnyInstance
      broken = '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>'

      expect { SvgConform.validate(broken, profile: profile, fix: true) }.to raise_error(fixes_called)
    end

    # The file path skips apply_fixes and rewrites through the profile.
    it "raises through the file path too" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "broken.svg")
        File.write(path, '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>')

        expect { SvgConform.validate_file(path, profile: profile, fix: true) }.to raise_error(fixes_called)
      end
    end
  end

  describe "the scan itself" do
    it "flags a direct call" do
      expect(apply_fixes_reference_count("validator.apply_fixes(svg)\n")).to eq(1)
    end

    it "flags a dynamic send by symbol" do
      expect(apply_fixes_reference_count("validator.send(:apply_fixes, svg)\n")).to eq(1)
    end

    it "ignores a comment that only mentions the name" do
      expect(apply_fixes_reference_count("# never call apply_fixes here\n")).to eq(0)
    end
  end
end
