# frozen_string_literal: true

require 'date'

# Rendering must not depend on the day it ran. Gantt derives its whole date
# range from the reference date, so an unpinned run produces different output
# every day from identical source, which makes any diff meaningless.
#
# The SVGs sit next to their .mmd sources and are tracked, because the gemspec
# ships whatever `git ls-files` returns and they go out to every user. So this
# task DOES dirty git, on purpose: regenerating is how a shipped example stays
# honest about what Sirena renders today.
EXAMPLE_TODAY = Date.new(2026, 1, 1)

# The only example sources legitimately unrenderable today.
EXPECTED_UNRENDERABLE_SOURCES = [
  'gantt/01-simple-timeline.beta.mmd',
  'packet/01-basic-packet.beta.mmd'
].freeze

# Keeps helper methods off Object; ExampleTasks itself remains top-level.
module ExampleTasks
  module_function

  # The one place an example's theme is decided. Both :generate and :validate
  # read it here so they cannot drift into rendering the same source two ways.
  def theme_for(mmd_file)
    yml_file = mmd_file.sub(/\.mmd\z/, '.yml')
    metadata = File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
    metadata['theme'] || 'default'
  end

  def validate_examples(examples_dir)
    failed = []
    known_unrenderable = []
    unexpectedly_renderable = []
    passed = 0
    total = 0

    puts "Validating examples..."
    puts ". rendered   K known unrenderable   F failure"
    puts ""

    Dir.glob(File.join(examples_dir, '*/*.mmd')).sort.each do |mmd_file|
      total += 1
      source = File.read(mmd_file)
      relative_path = mmd_file.sub(examples_dir + '/', '')
      expected_unrenderable = EXPECTED_UNRENDERABLE_SOURCES.include?(relative_path)

      begin
        theme = theme_for(mmd_file)
        Sirena.render(source, theme: theme, today: EXAMPLE_TODAY)
        if expected_unrenderable
          unexpectedly_renderable << relative_path
          print 'F'
        else
          passed += 1
          print '.'
        end
      rescue => e
        if expected_unrenderable
          known_unrenderable << { file: relative_path, error: e.message }
          print 'K'
        else
          failed << { file: relative_path, error: e.message }
          print 'F'
        end
      end
    end

    failure_count = failed.size + unexpectedly_renderable.size

    puts "\n\n"
    puts "=" * 60
    puts "Validation Results"
    puts "=" * 60
    renderable = total - known_unrenderable.size
    puts "Total:  #{total}"
    puts "Passed: #{passed} of #{renderable} renderable " \
         "(#{renderable.zero? ? 'n/a' : "#{(passed.to_f / renderable * 100).round(1)}%"})"
    puts "Known unrenderable: #{known_unrenderable.size}"
    puts "Failed: #{failure_count}"
    puts "=" * 60

    if known_unrenderable.any?
      puts "\nKnown unrenderable:"
      known_unrenderable.each do |f|
        puts "  ⚠️  #{f[:file]}"
        puts "    #{f[:error]}"
      end
    end

    if failure_count.positive?
      puts "\nFailures:"
      failed.each do |f|
        puts "  ✗ #{f[:file]}"
        puts "    #{f[:error]}"
      end
      unexpectedly_renderable.each do |file|
        puts "  ✗ #{file}"
        puts "    listed as known unrenderable but rendered successfully"
      end
      exit 1
    else
      puts "\n✅ All renderable examples validated successfully!"
    end
  end

  # An SVG whose source is gone still ships: git tracks it and the gemspec
  # packages it, and the loop below walks sources, so nothing ever visits it.
  # Delete it so generation leaves only outputs backed by current sources.
  #
  # `**` rather than `*/`, because the gemspec packages every SVG under
  # examples/ at any depth. A sweep one level deep left the ones directly
  # under examples/ for the conformance gate to fail on and a human to delete
  # by hand, which is how the two this branch removed were found.
  #
  # This treats every sourceless SVG under examples/ as an orphan, so a
  # hand-authored illustrative SVG there is destroyed by a routine run too.
  # The conformance gate refuses one anyway — it requires exactly one SVG per
  # source and none without — so the sweep enforces what the gate demands.
  def remove_orphan_svgs(examples_dir)
    orphans = Dir.glob(File.join(examples_dir, '**', '*.svg'))
      .reject { |svg| File.exist?(svg.sub(/\.svg\z/, '.mmd')) }

    orphans.sort.each do |svg_file|
      File.delete(svg_file)
      relative = svg_file.sub("#{examples_dir}/", '')
      puts "    removed #{relative}, which no longer has a source"
    end
  end

  # A source that stops rendering must not keep shipping its old SVG. Leaving
  # it behind means the packaged output is still there, still valid-looking,
  # and no longer true. The conformance gate detects a newly failing source
  # either way by matching the unrenderable sources by name; deletion is about
  # not shipping a stale picture, not about detection.
  def remove_failed_svg(svg_file)
    return unless File.exist?(svg_file)

    File.delete(svg_file)
    puts "    removed #{File.basename(svg_file)}, which no longer renders"
  end

  def handle_failed_svgs(failed_renders)
    unexpected_sources = failed_renders.map(&:first) - EXPECTED_UNRENDERABLE_SOURCES
    unless unexpected_sources.empty?
      puts "\n⚠️  Unexpected render failure: example sources failed to render."
      puts "   Unexpected: #{unexpected_sources.sort.join(', ')}; SVGs that did render have " \
           "already been rewritten, while nothing was deleted."
      exit 1
    end

    failed_renders.map(&:last).each { |svg_file| remove_failed_svg(svg_file) }
  end
end

namespace :examples do
  desc "Generate all example SVGs from source files"
  task :generate do
    require 'sirena'
    require 'yaml'
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)

    unless Dir.exist?(examples_dir)
      puts "⚠️  Examples directory not found: #{examples_dir}"
      puts "Run 'rake examples:init' to create the directory structure"
      exit 1
    end

    # Find all diagram type directories
    diagram_dirs = Dir.glob(File.join(examples_dir, '*')).select { |f| File.directory?(f) }

    total_generated = 0
    failed_renders = []

    diagram_dirs.sort.each do |dir|
      diagram_type = File.basename(dir)
      next if diagram_type == '.git' || diagram_type.start_with?('.')

      puts "\n📊 Generating examples for #{diagram_type}..."

      # Find all .mmd files
      mmd_files = Dir.glob(File.join(dir, '*.mmd'))

      if mmd_files.empty?
        puts "  ⚠️  No examples found for #{diagram_type}"
        next
      end

      mmd_files.sort.each do |mmd_file|
        basename = File.basename(mmd_file, '.mmd')
        svg_file = File.join(dir, "#{basename}.svg")

        begin
          # Render to SVG
          theme = ExampleTasks.theme_for(mmd_file)
          svg = Sirena.render(File.read(mmd_file), theme: theme, today: EXAMPLE_TODAY)

          # Write SVG
          File.write(svg_file, svg)

          puts "  ✓ #{basename}.svg"
          total_generated += 1
        rescue => e
          puts "  ✗ #{basename}.svg - ERROR: #{e.message}"
          relative_path = mmd_file.delete_prefix("#{examples_dir}/")
          failed_renders << [relative_path, svg_file]
        end
      end
    end

    ExampleTasks.handle_failed_svgs(failed_renders)
    ExampleTasks.remove_orphan_svgs(examples_dir)
    puts "\n" + "=" * 60
    puts "✅ Example generation complete!"
    puts "   Generated: #{total_generated}"
    puts "   Failed: #{failed_renders.size}"
    puts "=" * 60
  end

  desc "Copy generated examples to docs/assets/examples"
  task :copy_to_docs do
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)
    docs_assets_dir = File.expand_path('../../docs/assets/examples', __dir__)

    FileUtils.mkdir_p(docs_assets_dir)

    total_copied = 0

    Dir.glob(File.join(examples_dir, '*')).select { |f| File.directory?(f) }.sort.each do |dir|
      diagram_type = File.basename(dir)
      target_dir = File.join(docs_assets_dir, diagram_type)

      svg_files = Dir.glob(File.join(dir, '*.svg'))
      next if svg_files.empty?

      FileUtils.mkdir_p(target_dir)

      svg_files.each do |svg_file|
        FileUtils.cp(svg_file, target_dir)
        total_copied += 1
      end

      puts "✓ Copied #{svg_files.size} #{diagram_type} examples to docs/assets/examples/"
    end

    puts "\n✅ #{total_copied} examples copied to documentation!"
  end

  desc "Generate AsciiDoc include files for documentation"
  task :generate_docs do
    require 'yaml'
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)
    docs_examples_dir = File.expand_path('../../docs/_diagram_types/examples', __dir__)

    FileUtils.mkdir_p(docs_examples_dir)

    diagram_dirs = Dir.glob(File.join(examples_dir, '*')).select { |f| File.directory?(f) }

    diagram_dirs.sort.each do |dir|
      diagram_type = File.basename(dir)
      next if diagram_type == '.git' || diagram_type.start_with?('.')

      mmd_files = Dir.glob(File.join(dir, '*.mmd')).sort
      next if mmd_files.empty?

      # Generate AsciiDoc include file
      adoc_file = File.join(docs_examples_dir, "#{diagram_type}-examples.adoc")

      content = []
      content << "// Auto-generated examples for #{diagram_type}"
      content << "// Generated by rake examples:build"
      content << ""

      mmd_files.each_with_index do |mmd_file, index|
        basename = File.basename(mmd_file, '.mmd')
        yml_file = File.join(dir, "#{basename}.yml")

        # Read metadata
        metadata = File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
        title = metadata['title'] || basename.split('-').map(&:capitalize).join(' ')
        description = metadata['description'] || 'Example diagram'
        complexity = metadata['complexity'] || 'basic'
        use_cases = metadata['use_cases'] || []

        content << "==== Example #{index + 1}: #{title}"
        content << ""
        content << ".#{description}"

        if !use_cases.empty? || complexity != 'basic'
          content << "[NOTE]"
          content << "===="
          content << "Complexity: #{complexity.capitalize}"
          if !use_cases.empty?
            content << " +"
            content << "Use Cases: #{use_cases.join(', ')}"
          end
          content << "===="
        end

        content << ""
        content << ".Source Code"
        content << "[source,mermaid]"
        content << "----"
        content << File.read(mmd_file).strip
        content << "----"
        content << ""
        content << ".Rendered Output"
        content << "image::../../assets/examples/#{diagram_type}/#{basename}.svg[#{title},600]"
        content << ""
        content << "'''"
        content << ""
      end

      File.write(adoc_file, content.join("\n"))
      puts "✓ Generated #{diagram_type}-examples.adoc (#{mmd_files.size} examples)"
    end

    puts "\n✅ Documentation includes generated!"
  end

  desc "Validate all examples (parse and render)"
  task :validate do
    require 'sirena'
    require 'yaml'

    examples_dir = File.expand_path('../../examples', __dir__)
    ExampleTasks.validate_examples(examples_dir)
  end

  desc "Generate all examples and copy to docs"
  task :build => [:generate, :generate_docs, :copy_to_docs]

  desc "Create example template for a diagram type"
  task :create, [:type, :name] do |t, args|
    require 'fileutils'

    type = args[:type]
    name = args[:name]

    if type.nil? || name.nil?
      puts "Usage: rake examples:create[type,name]"
      puts "Example: rake examples:create[flowchart,basic-flow]"
      exit 1
    end

    examples_dir = File.expand_path('../../examples', __dir__)
    type_dir = File.join(examples_dir, type)

    FileUtils.mkdir_p(type_dir)

    # Find next number
    existing = Dir.glob(File.join(type_dir, '*.mmd')).map do |f|
      File.basename(f).split('-').first.to_i
    end.max || 0
    number = existing + 1

    basename = format("%02d-%s", number, name)

    # Create .mmd file
    mmd_file = File.join(type_dir, "#{basename}.mmd")
    File.write(mmd_file, "#{type}\n  A --> B\n")

    # Create .yml file
    yml_file = File.join(type_dir, "#{basename}.yml")
    yml_content = <<~YAML
      title: "#{name.split('-').map(&:capitalize).join(' ')}"
      description: "Description of this example"
      complexity: basic
      keywords:
        - #{type}
      use_cases:
        - "Example use case"
      theme: default
    YAML
    File.write(yml_file, yml_content)

    puts "✓ Created #{basename}.mmd"
    puts "✓ Created #{basename}.yml"
    puts "\nEdit these files and run: rake examples:generate"
  end

  desc "List all examples with status"
  task :list do
    require 'yaml'

    examples_dir = File.expand_path('../../examples', __dir__)

    unless Dir.exist?(examples_dir)
      puts "Examples directory not found: #{examples_dir}"
      puts "Run 'rake examples:init' to create it"
      exit 1
    end

    diagram_dirs = Dir.glob(File.join(examples_dir, '*')).select { |f| File.directory?(f) }

    total_examples = 0

    diagram_dirs.sort.each do |dir|
      diagram_type = File.basename(dir)
      next if diagram_type == '.git' || diagram_type.start_with?('.')

      examples = Dir.glob(File.join(dir, '*.mmd'))
      total_examples += examples.size

      puts "\n#{diagram_type.upcase.tr('-', ' ')} (#{examples.size} examples)"
      puts "─" * 60

      if examples.empty?
        puts "  (no examples yet)"
        next
      end

      examples.sort.each do |mmd_file|
        basename = File.basename(mmd_file, '.mmd')
        yml_file = File.join(dir, "#{basename}.yml")
        svg_file = File.join(dir, "#{basename}.svg")

        metadata = File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
        title = metadata['title'] || basename
        complexity = metadata['complexity'] || 'basic'

        svg_status = File.exist?(svg_file) ? "✓" : "✗"

        puts "  #{svg_status} #{basename}: #{title} [#{complexity}]"
      end
    end

    puts "\n" + "=" * 60
    puts "Total: #{total_examples} examples across #{diagram_dirs.size} diagram types"
    puts "=" * 60
  end

  desc "Initialize examples directory structure"
  task :init do
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)

    # Create main examples directory
    FileUtils.mkdir_p(examples_dir)

    # Create README
    readme_content = <<~README
      # Sirena Examples

      This directory contains example diagrams for all supported diagram types.

      ## Structure

      Each diagram type has its own directory with:
      - `*.mmd` - Mermaid source files
      - `*.yml` - Metadata for each example
      - `*.svg` - Rendered output, regenerated in place and committed

      ## Usage

      ```bash
      # Generate all SVGs
      rake examples:generate

      # Create a new example
      rake examples:create[flowchart,my-example]

      # Validate all examples
      rake examples:validate

      # List all examples
      rake examples:list

      # Build everything (generate + docs + copy)
      rake examples:build
      ```

      ## Adding Examples

      1. Create example files:
         ```bash
         rake examples:create[type,name]
         ```

      2. Edit the `.mmd` and `.yml` files

      3. Generate SVG:
         ```bash
         rake examples:generate
         ```

      4. Build documentation:
         ```bash
         rake examples:build
         ```

      ## Example Metadata

      Each `.yml` file should contain:

      ```yaml
      title: "Example Title"
      description: "What this example demonstrates"
      complexity: basic  # basic, intermediate, advanced
      keywords:
        - keyword1
        - keyword2
      use_cases:
        - "Use case description"
      theme: default  # default, dark, light, high-contrast
      ```
    README

    File.write(File.join(examples_dir, 'README.md'), readme_content)

    # Create .gitignore
    gitignore_content = <<~GITIGNORE
      # Stale generated/ directories from older checkouts. Nothing writes them
      # now — the shipped SVGs sit beside their sources — but leaving the rule
      # keeps an old working copy quiet and stops `git add examples/` sweeping
      # stale output back in.
      */generated/

      # Ignore macOS files
      .DS_Store

      # Ignore editor files
      *.swp
      *.swo
      *~
    GITIGNORE

    File.write(File.join(examples_dir, '.gitignore'), gitignore_content)

    puts "✓ Created examples/ directory"
    puts "✓ Created README.md"
    puts "✓ Created .gitignore"
    puts "\n✅ Examples directory initialized!"
    puts "\nNext steps:"
    puts "  1. Create examples: rake examples:create[type,name]"
    puts "  2. Generate SVGs: rake examples:generate"
    puts "  3. Build docs: rake examples:build"
  end

  desc "Clean stale generated directories and documentation copies"
  task :clean do
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)
    docs_assets_dir = File.expand_path('../../docs/assets/examples', __dir__)
    docs_examples_dir = File.expand_path('../../docs/_diagram_types/examples', __dir__)

    # Clean the stale generated/ directories older checkouts left behind.
    # The shipped SVGs sit beside their sources now and are not touched.
    Dir.glob(File.join(examples_dir, '*/generated')).each do |dir|
      FileUtils.rm_rf(dir)
      puts "✓ Removed #{dir}"
    end

    # Clean docs assets
    if Dir.exist?(docs_assets_dir)
      FileUtils.rm_rf(docs_assets_dir)
      puts "✓ Removed #{docs_assets_dir}"
    end

    # Clean docs includes
    if Dir.exist?(docs_examples_dir)
      FileUtils.rm_rf(docs_examples_dir)
      puts "✓ Removed #{docs_examples_dir}"
    end

    puts "\n✅ Cleaned stale generated directories and documentation copies!"
  end
end
