module Greeter
  def self.greet(name, shout: false)
    greeting = "Hello, #{name}!"
    shout ? greeting.upcase : greeting
  end
end
