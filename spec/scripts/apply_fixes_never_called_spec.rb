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
    gemspec.files.grep(SHIPPED_CODE).map do |f|
      File.join(root, f)
    end.select { |f| File.file?(f) }.sort
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

  def trap_new_instances(klass, raised_methods, error, returned_methods = {})
    allow(klass)
      .to receive(:new)
      .and_wrap_original do |constructor, *args, **kwargs, &block|
      instance = constructor.call(*args, **kwargs, &block)
      trap_instance(instance, raised_methods, error, returned_methods)
      instance
    end
  end

  def trap_instance(instance, raised_methods, error, returned_methods)
    raised_methods.each do |name|
      allow(instance).to receive(name).and_raise(error)
    end
    return if returned_methods.empty?

    allow(instance).to receive_messages(returned_methods)
  end

  def validate_broken_svg
    SvgConform.validate(broken_svg, profile: profile, fix: true)
  end

  def validate_broken_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.svg")
      File.write(path, broken_svg)
      SvgConform.validate_file(path, profile: profile, fix: true)
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
    "exe" => %r{/exe/[^/]+\z},
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
    let(:broken_svg) { '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' }
    let(:conformant_svgs) do
      %w[flowchart sequence class_diagram state_diagram er_diagram user_journey
         xy_chart sankey].map do |type|
        input = File.join(repo_root, "spec", "fixtures", type, "input.mmd")
        Sirena::Engine.new.render(File.read(input))
      end
    end

    before do
      require "svg_conform"
      guarded_methods = {
        SvgConform::ValidationResult => [:apply_fixes],
        SvgConform::Fixer => %i[apply_fix apply_fixes apply_validation_fixes],
        SvgConform::Profile => [:apply_remediations],
        SvgConform::RemediationEngine => [:apply_remediations],
      }
      guarded_methods.each do |klass, names|
        trap_new_instances(klass, names, fixes_called)
      end
      trap_new_instances(
        SvgConform::ValidationResult,
        [:apply_fixes],
        fixes_called,
        fixable?: true,
      )
      allow(SvgConform::Profiles.get(profile))
        .to receive(:apply_remediations).and_raise(fixes_called)
    end

    it "does not invoke fixes while validating Sirena output" do
      Dir.mktmpdir do |dir|
        conformant_svgs.each_with_index do |svg, i|
          path = File.join(dir, "#{i}.svg")
          File.write(path, svg)

          expect(SvgConform.validate(svg, profile: profile,
                                          fix: true)).to be_valid
          expect(SvgConform.validate_file(path, profile: profile,
                                                fix: true)).to be_valid
        end
      end
    end

    it "raises when a fixable violation reaches it, so the trap is live" do
      expect { validate_broken_svg }.to raise_error(fixes_called)
    end

    # The file path skips apply_fixes and rewrites through the profile.
    it "raises through the file path too" do
      expect { validate_broken_file }.to raise_error(fixes_called)
    end
  end

  describe "the scan itself" do
    it "flags a direct call" do
      source = "validator.apply_fixes(svg)\n"

      expect(apply_fixes_reference_count(source)).to eq(1)
    end

    it "flags a dynamic send by symbol" do
      source = "validator.send(:apply_fixes, svg)\n"

      expect(apply_fixes_reference_count(source)).to eq(1)
    end

    it "ignores a comment that only mentions the name" do
      source = "# never call apply_fixes here\n"

      expect(apply_fixes_reference_count(source)).to eq(0)
    end
  end
end
