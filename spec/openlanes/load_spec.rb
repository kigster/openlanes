# frozen_string_literal: true

require "open3"

RSpec.describe "openlanes load path" do
  it "loads the gem entrypoint without eager-load NameError failures" do
    output, status = Open3.capture2e(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      "require 'openlanes'; puts 'loaded'"
    )

    expect([status.success?, output]).to eq([true, "loaded\n"])
  end
end
