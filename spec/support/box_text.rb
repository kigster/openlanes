# frozen_string_literal: true

# What a box says, without the box.
#
# dry-cli-ui wraps a message to the box's width and draws a border either side
# of every line, so a sentence that wraps reads `openlanes unblock │ │ 001.00`
# in the raw stream. Stripping the frame and collapsing the whitespace lets an
# example assert on the sentence, whatever width the box happened to be.
module BoxText
  BORDER = "│┌┐└┘─├┤"

  # @param text [String] captured STDERR
  # @return [String]
  def unwrapped(text) = text.tr(BORDER, " ").gsub(/\s+/, " ")
end
