# frozen_string_literal: true

require "tmpdir"

module OpenLanes
  module Execution
    class Executor
      # Where every invocation's raw stream is written.
      module Traces
        # Where the raw stream of each invocation is kept.
        #
        # Under `run -j` several agents work at once, and more than one
        # `openlanes` may be driving the same checkout, so a trace is named
        # per invocation rather than shared. To get an agent's final answer back
        # out of one afterwards:
        #
        #   jq -r 'select(.type=="result").result' <trace>
        #
        # and to replay what it did, tool call by tool call:
        #
        #   jq -r 'select(.type=="assistant")
        #          | .message.content[]?
        #          | select(.type=="tool_use")
        #          | "\(.name) \(.input|tostring[0:80])"' <trace>
        #
        # Outside the repository on purpose: the harness checks afterwards that the
        # agent moved nothing it should not have, and a megabyte of NDJSON dropped
        # into the working tree is exactly the kind of thing that check would then
        # have to learn to ignore.
        DIR = File.join(Dir.tmpdir, "openlanes-traces")
      end
    end
  end
end
