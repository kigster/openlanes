# frozen_string_literal: true

# main once carried `openlanes (4.0.0)` in Gemfile.lock under a 4.0.1 gem,
# because the version was bumped by hand and nobody relocked. bin/bump-version
# keeps the two together; this example catches a bump made any other way.
RSpec.describe "Gemfile.lock" do
  let(:lock) { File.read(File.expand_path("../../../Gemfile.lock", __dir__)) }
  let(:locked) { OpenLanes::Release::Lockfile.new(lock).entries }

  it "records openlanes at all, both under PATH and under CHECKSUMS" do
    expect(locked).not_to be_empty
  end

  it "records openlanes at OpenLanes::VERSION in every entry" do
    expect(locked.uniq).to eq([OpenLanes::VERSION]),
      "Gemfile.lock says openlanes (#{locked.uniq.join(", ")}), version.rb says " \
      "#{OpenLanes::VERSION}. Bump with `just bump <version>`, which relocks."
  end
end
