# frozen_string_literal: true

# The slice of the app port range that the examples starting real servers
# reserve from. Every suite used to scan up from 11100, so two suites run at
# once from sibling worktrees took the same port within milliseconds: a
# `--silent` fixture then "answered" through the other suite's server, and
# the timeout example saw nothing raised. A window picked by pid keeps
# concurrent suites apart; it does not change what `Ports` hands out in use.
module PortWindow
  # Ports per window: room for every process an example starts.
  SIZE = 100

  # @return [Hash{Symbol => Integer}] `floor:` and `ceiling:` for `Ports.new`
  def self.bounds(pid = Process.pid)
    floor = OpenLanes::Apps::Ports::FLOOR
    windows = (OpenLanes::Apps::Ports::CEILING - floor + 1) / SIZE
    start = floor + ((pid % windows) * SIZE)
    { floor: start, ceiling: start + SIZE - 1 }
  end
end
