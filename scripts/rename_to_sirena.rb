#!/usr/bin/env ruby
# Script to rename sirena to sirena throughout the codebase

require 'fileutils'

PROJECT_ROOT = File.expand_path('../..', __FILE__)

puts "Renaming project from sirena to sirena..."
puts "Project root: #{PROJECT_ROOT}"

# Step 1: Rename directories
puts "\n1. Renaming directories..."
Dir.chdir(PROJECT_ROOT) do
  if Dir.exist?('lib/sirena')
    FileUtils.mv('lib/sirena', 'lib/sirena')
    puts "  ✓ Renamed lib/sirena -> lib/sirena"
  end
end

# Step 2: Rename files
puts "\n2. Renaming files..."
Dir.chdir(PROJECT_ROOT) do
  # Rename gemspec
  if File.exist?('sirena.gemspec')
    FileUtils.mv('sirena.gemspec', 'sirena.gemspec')
    puts "  ✓ Renamed sirena.gemspec -> sirena.gemspec"
  end

  # Rename executable
  if File.exist?('exe/sirena')
    FileUtils.mv('exe/sirena', 'exe/sirena')
    puts "  ✓ Renamed exe/sirena -> exe/sirena"
  end
end

# Step 3: Update file contents
puts "\n3. Updating file contents..."
replacements = {
  'sirena' => 'sirena',
  'sirena' => 'sirena',
  'Sirena' => 'Sirena',
  'SIRENA' => 'SIRENA'
}

files_to_update = Dir.glob("#{PROJECT_ROOT}/**/*.{rb,gemspec,md,adoc,rake}",
                           File::FNM_DOTMATCH).reject do |f|
  f.include?('/.git/') ||
  f.include?('/vendor/') ||
  f.include?('/node_modules/')
end

files_updated = 0
files_to_update.each do |file_path|
  content = File.read(file_path)
  original = content.dup

  replacements.each do |old_val, new_val|
    content.gsub!(old_val, new_val)
  end

  if content != original
    File.write(file_path, content)
    files_updated += 1
    puts "  ✓ Updated #{file_path.sub(PROJECT_ROOT + '/', '')}"
  end
end

puts "\n✓ Rename complete!"
puts "  - #{files_updated} files updated"
puts "\nNext steps:"
puts "  1. Review changes with: git diff"
puts "  2. Run tests: bundle exec rspec"
puts "  3. Update any remaining manual references"