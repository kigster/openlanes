# frozen_string_literal: true

require "stringio"

# A standard stream captured for an assertion.
#
# TTY::Screen asks $stdout, $stdin and $stderr for the terminal width with
# `ioctl` and rescues only SystemCallError, so a bare StringIO standing in for
# one of them raises NoMethodError from inside the box drawing code instead of
# falling back to a default width. A captured stream is a closed terminal, so
# it answers like one.
class CapturedStream < StringIO
  # Runs the block with $stdout and $stderr captured and an `exit` caught,
  # for a command whose refusals end the process.
  #
  # @return [Array(String, String, Integer, nil)] out, err, and the status it exited with
  def self.capture
    out, err, saved = new, new, [$stdout, $stderr]
    $stdout, $stderr = out, err
    begin
      yield
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = saved
    end
    [out.string, err.string, status]
  end

  def ioctl(*) = raise(Errno::ENOTTY)
end
