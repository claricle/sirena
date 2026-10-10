# frozen_string_literal: true

# Validation messages of a built IR model, for specs that pin each rule.
module IrValidationHelpers
  def ir_messages(model_class, **attributes)
    model_class.new(**attributes).validate.map(&:message)
  end
end

RSpec.configure { |config| config.include IrValidationHelpers }
