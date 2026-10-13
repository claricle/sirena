# frozen_string_literal: true

module SpecSupport
  module RepositoryPaths
    ROOT = File.expand_path("../..", __dir__)

    module_function

    def path(relative)
      File.expand_path(relative, ROOT)
    end
  end
end
