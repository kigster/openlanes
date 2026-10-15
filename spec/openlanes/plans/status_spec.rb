# frozen_string_literal: true

# Decision N2: every state emoji is one code point that is an emoji by
# default, and the emoji each state wore before still resolve to it.
RSpec.describe OpenLanes::Plans::Status do
  OpenLanes::Plans::STATUSES.each do |status|
    describe status.emoji do
      it "is one code point" do
        expect(status.emoji.codepoints.size).to eq(1)
      end

      it "carries no variation selector" do
        expect(status.emoji).not_to include("\u{FE0F}")
      end

      it "is an emoji without being asked to be" do
        expect(status.emoji).to match(/\p{Emoji_Presentation}/)
      end
    end
  end

  {
    "⚪️" => "⚪", "⭐️" => "⭐", "⭕️" => "⭕", "🅱️" => "🛑", "🅱" => "🛑", "☢️" => "💤", "🕰️" => "⏪"
  }.each do |was, now|
    it "resolves the old #{was} to the same state as #{now}" do
      expect(OpenLanes::Plans.status_for_emoji(was)).to equal(OpenLanes::Plans.status_for_emoji(now))
      expect(OpenLanes::Plans.status_for_emoji(now).emoji).to eq(now)
    end
  end

  it "never writes an old emoji back out" do
    expect(OpenLanes::Plans::STATUSES.map(&:emoji) & OpenLanes::Plans::LEGACY_EMOJI.keys).to be_empty
  end
end
