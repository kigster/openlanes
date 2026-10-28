class Invoice
  TAX_RATE = 0.0825

  def initialize(subtotal) = @subtotal = subtotal

  def total = @subtotal + (@subtotal * TAX_RATE).round
end
