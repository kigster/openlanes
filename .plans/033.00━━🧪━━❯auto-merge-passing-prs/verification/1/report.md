# Verification, round 1

Verdict: verified

## Steps

1. A passing, verified, green, clean PR is merged by the engine: passed
2. A PR missing any one condition is not: passed
3. After a merge, other plan branches are rebased, queued until idle; HEAD and uncommitted work protected: passed

Checked through `spec/openlanes/engine/merging_spec.rb` (35 examples, 0 failures); no app declared.
