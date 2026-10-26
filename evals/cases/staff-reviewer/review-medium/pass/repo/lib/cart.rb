class Cart
  class InvalidQuantity < ArgumentError; end

  def add(sku, quantity)
    raise InvalidQuantity if quantity.negative?

    quantity
  end
end
