# frozen_string_literal: true

# Points {OpenLanes::Log} at a file the example owns, at debug so nothing it
# writes is filtered out. spec_helper resets it after every example.
module LogHelper
  # @param path [String]
  # @param format [String] "standard" or "json"
  # @param name [String] what the lines are signed with
  # @return [OpenLanes::Log::Settings]
  def open_log(path, format: "standard", name: "engine")
    OpenLanes::Log.setup(OpenLanes::Log::Settings.new(file: path, level: "debug", format:), name:)
  end
end
