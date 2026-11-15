# Blocked

## B1 The arbitrator ruled no_go at the rejection cap

⚖️ Ruling (cap): no_go

> F5 is confirmed in the code. When a pair's first builder finishes, the plan holds at 🎨 and that builder's red gate verdict is never checked (rename.rb:76-80). The last builder gets the mail and the rerun, and the hold leaves the plan in a state backend-coder does not handle. The spec's "bounce to the builder" fails for every paired plan, and no spec covers a pair. F6 (bounce count never reset) is minor.

a) Send it back to the builders for one more round. (Recommended)
b) Close the pull request and replan.
