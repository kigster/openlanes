require_relative "greeter/formatter"

# Greets people. Restructured around a formatter so salutations can vary.
module Greeter
  DEFAULT_SALUTATION = "Hello"

  class << self
    # @param name [String]
    # @param salutation [String]
    # @return [String]
    def greet(name, salutation: DEFAULT_SALUTATION)
      Formatter.new(salutation:).format(name)
    end
  end
end
