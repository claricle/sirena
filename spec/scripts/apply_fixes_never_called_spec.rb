# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "svg_conform apply_fixes", type: :task do
  include ApplyFixesScan

  let(:repo_root) { File.expand_path("../..", __dir__) }

  it "is referenced nowhere in shipped code" do
    expect(apply_fixes_references(shipped_files(repo_root))).to be_empty
  end

  {
    "lib ruby" => %r{/lib/.*\.rb\z},
    "lib rake task" => %r{/lib/.*\.rake\z},
    "exe" => %r{/exe/[^/]+\z},
    "scripts" => %r{/scripts/.*\.rb\z},
    "Rakefile" => %r{/Rakefile\z},
    "gemspec" => %r{/[^/]+\.gemspec\z}
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
        Sirena::Engine.new.render(File.read(File.join(repo_root, "spec/fixtures", type, "input.mmd")))
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
    def scan(source)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "seeded.rb")
        File.write(path, source)
        apply_fixes_references([path]).size
      end
    end

    it "flags a direct call" do
      expect(scan("validator.apply_fixes(svg)\n")).to eq(1)
    end

    it "flags a dynamic send by symbol" do
      expect(scan("validator.send(:apply_fixes, svg)\n")).to eq(1)
    end

    it "ignores a comment that only mentions the name" do
      expect(scan("# never call apply_fixes here\n")).to eq(0)
    end
  end
end
