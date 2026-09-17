# frozen_string_literal: true

require "open3"

module ComponentRequireHelper
  # Shells out to a real subprocess so a component file's `require` can be
  # checked in isolation -- $LOADED_FEATURES would make a second in-process
  # `require "sirena/parser"` a silent no-op once spec_helper has already
  # loaded the whole gem.
  def require_standalone(path)
    Open3.capture2e("ruby", "-Ilib", "-e", "require #{path.inspect}")
  end
end

RSpec.configure do |config|
  config.include ComponentRequireHelper
end
