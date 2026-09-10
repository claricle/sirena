# frozen_string_literal: true

require_relative 'style_cascade/css_validity'
require_relative 'style_cascade/resolved_styles'
require_relative 'style_cascade/resolver'

module Sirena
  # Reproduces mermaid's own classDef style-resolution cascade
  # (`styles2Map` / `ErDB#addClass` / `compileStyles` / `userNodeOverrides`
  # / `isLabelStyle`) as one ordered pipeline, rather than a set of
  # independent lookups added one probed input at a time.
  #
  # Entry point: `Resolver.new(class_defs).resolve(assigned_classes)`
  # returns a `ResolvedStyles`, which exposes the two real read strategies
  # mermaid applies depending on how an element is drawn
  # (`ResolvedStyles#attributed` for an exact-key/unvalidated read,
  # `ResolvedStyles#cascade` for a case-insensitive browser-cascade read)
  # plus `ResolvedStyles#label_color` for an entity's text color.
  #
  # This module has no dependency on any specific diagram type — it is
  # wired into `Renderer::ErDiagram` today because that is the diagram
  # type this card is about, not because the logic is ER-specific.
  module StyleCascade
  end
end
