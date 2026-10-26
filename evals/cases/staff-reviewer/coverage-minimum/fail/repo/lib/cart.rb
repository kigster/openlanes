class Cart
  def initialize = @lines = []

  def add(price, quantity) = @lines << [price, quantity]

  def total
    cents = @lines.sum { |price, quantity| price * quantity }
    cents.is_a?(Float) ? cents.round : cents
  end
end
