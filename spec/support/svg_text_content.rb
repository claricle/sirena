# frozen_string_literal: true

module SvgTextContent
  # `#content` is a `collection: true` attribute (see `Svg::Text#simple_body`);
  # which lutaml-model version is loaded determines whether a scalar
  # assignment reads back as a scalar or a one-element Array. Always read it
  # through this helper, the same way production code does
  # (`Array(content).join`), never raw `#content`.
  def svg_text_content(element)
    Array(element.content).join
  end
end

RSpec.configure do |config|
  config.include SvgTextContent
end
