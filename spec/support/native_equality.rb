# frozen_string_literal: true

# Compares the Rust runtime's SVG with the Ruby pipeline's for Mermaid corpus
# paths. Needs `sirena-native` loaded (see runtime_native_equality_spec.rb).
module NativeEquality
  CORPUS_ROOT = File.expand_path("../mermaid", __dir__)

  # Corpus paths that Ruby renders, grouped by diagram type directory.
  def self.paths_by_type
    listing = File.join(CORPUS_ROOT, "corpus-renderable.txt")
    File.readlines(listing, chomp: true).group_by do |path|
      path.split("/").first
    end
  end

  # @return [Hash] :same count, :unported and :different path lists
  def self.compare(paths)
    ruby = Sirena::Engine.new
    tally = { same: 0, unported: [], different: [] }
    paths.each { |path| record(tally, path, ruby) }
    tally
  end

  def self.record(tally, path, ruby)
    source = File.read(File.join(CORPUS_ROOT, path))
    if Sirena::Native.library.render(source).b == ruby.render(source).b
      tally[:same] += 1
    else
      tally[:different] << path
    end
  rescue Sirena::Native::Unported
    tally[:unported] << path
  end
  private_class_method :record
end
