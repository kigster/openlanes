module Greeter
  # Turns a name into a greeting.
  class Formatter
    def initialize(salutation:)
      @salutation = salutation
    end

    # @param name [String]
    # @return [String]
    def format(name) = "#{@salutation}, #{name.strip}!"
  end
end
