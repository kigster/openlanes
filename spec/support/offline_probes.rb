# frozen_string_literal: true

# A probe runner on which no CLI is installed, so nothing it is asked starts
# a process. Every example gets it (see the hook below); examples about the
# probes hand in a runner of their own.
class OfflineProbeRunner
  # @return [nil] nothing is installed
  def which(_executable) = nil

  # @return [OpenLanes::Adapters::ProbeRunner::Result]
  def call(*argv) = OpenLanes::Adapters::ProbeRunner::Result.new(stdout: "", stderr: "offline: #{argv.first}", status: nil)
end

# A runner that answers each argv from a table, for examples about one
# adapter's probe.
class ScriptedProbeRunner
  # @param installed [Array<String>] the executables on its PATH
  # @param answers [Hash{Array<String> => OpenLanes::Adapters::ProbeRunner::Result}]
  def initialize(installed:, answers: {})
    @installed = installed
    @answers = answers
    @calls = []
  end

  # @return [Array<Array<String>>] every argv asked, in order
  attr_reader :calls

  # @return [String, nil]
  def which(executable) = @installed.include?(executable) ? "/usr/local/bin/#{executable}" : nil

  # @return [OpenLanes::Adapters::ProbeRunner::Result]
  def call(*argv)
    @calls << argv
    @answers.fetch(argv) { OpenLanes::Adapters::ProbeRunner::Result.new(stdout: "", stderr: "unscripted", status: 1) }
  end
end

RSpec.configure do |config|
  config.before { OpenLanes::Adapters.probe_runner = OfflineProbeRunner.new }
  config.after { OpenLanes::Adapters.probe_runner = nil }
end
