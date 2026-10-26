class Cart
  class InvalidQuantity < ArgumentError; end

  def initialize = @lines = {}

  def add(sku, quantity)
    raise InvalidQuantity, "quantity must be at least 1, got #{quantity}" if quantity < 1

    @lines[sku] = quantity
  end
end
