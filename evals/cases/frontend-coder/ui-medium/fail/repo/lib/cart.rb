class Cart
  class InvalidQuantity < ArgumentError
    def message = "quantity must be at least 1"
  end
end
