# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Include
        # Finds an included file, and only inside the allowed roots: the
        # directory of the source being rendered and the include-path
        # entries, all resolved through symlinks.
        class Finder
          URL = %r{\A\w[\w+.-]*://}
          private_constant :URL

          # @param base_dir [String, nil]
          # @param include_path [Array<String>, String, nil] directories,
          #   or a String of them joined by File::PATH_SEPARATOR
          def initialize(base_dir, include_path)
            extra = Array(include_path).flat_map do |entry|
              entry.to_s.split(File::PATH_SEPARATOR)
            end
            @roots = [base_dir, *extra].compact.filter_map { |d| real(d) }
          end

          # @param name [String] the path as written in the directive
          # @param dir [String, nil] directory of the including file
          # @return [String] the real path of the file
          # @raise [Error] a URL, or a file not found inside the roots
          def locate(name, dir)
            if name.match?(URL)
              raise Error, "PlantUML include of a URL is not supported: #{name}"
            end

            found = candidates(name, dir).filter_map { |c| allowed(c) }.first
            found || raise(Error, "cannot include #{name}")
          end

          private

          def candidates(name, dir)
            return [name] if File.absolute_path?(name)

            [dir, *@roots].compact.uniq.map { |root| File.join(root, name) }
          end

          def allowed(candidate)
            path = real(candidate)
            path if path && File.file?(path) && @roots.any? do |root|
              path.start_with?(File.join(root, ""))
            end
          end

          def real(path)
            File.realpath(path)
          rescue SystemCallError
            nil
          end
        end
      end
    end
  end
end
