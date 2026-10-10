# frozen_string_literal: true

desc "Measure layout parity and write scoreboard/layout-parity.json"
task :layout_parity do
  require_relative "support/layout_parity"
  puts Sirena::LayoutParityScoreboard.record!
rescue Sirena::LayoutParityScoreboard::DriftError => e
  warn e.message
  abort "layout_parity: FAILED"
end

namespace :layout_parity do
  desc "Fail when live layout parity differs from its committed scoreboard"
  task :check do
    require_relative "support/layout_parity"
    puts Sirena::LayoutParityScoreboard.check!
  rescue Sirena::LayoutParityScoreboard::DriftError => e
    warn e.message
    abort "layout_parity:check: FAILED"
  end
end
