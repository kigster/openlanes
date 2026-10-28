# The one sales-tax rate the shop charges.
module Tax
  RATE = 0.0825

  def self.on(cents) = (cents * RATE).round
end
