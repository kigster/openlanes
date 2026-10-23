# frozen_string_literal: true

# rubocop:disable RSpec/Output -- this is `gh`, and what it prints is its answer

# What `gh` would have answered, from a JSON file the spec writes and reads
# back: `$FAKE_GH_STATE`. Every call's argv is appended to `$FAKE_GH_LOG`,
# one JSON array per line, so a spec can assert what was asked of GitHub.
#
# It knows only the calls openlanes makes, and fails loudly on any other, so
# a new call shows up as a failing spec rather than a silent success.

require "json"

STATE = ENV.fetch("FAKE_GH_STATE")
File.open(ENV.fetch("FAKE_GH_LOG"), "a") { |f| f.puts(JSON.generate(ARGV)) }

state = File.file?(STATE) ? JSON.parse(File.read(STATE)) : {}
state["labels"] ||= []
state["colours"] ||= {}
state["prs"] ||= {}
state["next"] ||= 1

def save(state) = File.write(STATE, JSON.pretty_generate(state))

def fail_with(message, code = 1)
  warn(message)
  exit(code)
end

def flag(name) = (i = ARGV.index(name)) && ARGV[i + 1]

def flags(name) = ARGV.each_index.select { ARGV[it] == name }.map { ARGV[it + 1] }

def pr!(state, ref) = state["prs"][ref.to_s[/(\d+)\z/, 1].to_s] || fail_with("GraphQL: Could not resolve to a PullRequest with the number of #{ref}.")

def row(number, pull)
  { "number" => number.to_i, "title" => pull["title"], "url" => pull["url"], "headRefName" => pull["branch"],
    "headRefOid" => pull.fetch("head", "c0ffee#{number.to_i}"),
    "files" => [], "state" => pull["state"], "isDraft" => false, "mergedAt" => pull["merged_at"], "body" => "",
    "labels" => pull["labels"].map { { "name" => it } },
    "mergeStateStatus" => pull.fetch("merge_state", "CLEAN"),
    "baseRefName" => pull.fetch("base", "main"),
    "mergeCommit" => pull["merge_commit"] && { "oid" => pull["merge_commit"] } }
end

case ARGV.take(2)
in ["auth", "status"]
  exit 0
in ["label", "create"]
  name = ARGV[2]
  fail_with(%(label with name "#{name}" already exists; use `--force` to update its color and description)) if state["labels"].include?(name)
  state["labels"] << name
  state["colours"][name] = flag("--color")
  save(state)
in ["label", "list"]
  puts JSON.generate(state["labels"].map { { "name" => it, "color" => state["colours"].fetch(it, "ededed").downcase } })
in ["label", "edit"]
  name = ARGV[2]
  fail_with(%(label with name "#{name}" not found)) unless state["labels"].include?(name)
  state["colours"][name] = flag("--color")
  save(state)
in ["pr", "create"]
  number = state["next"]
  state["next"] += 1
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  url = "https://github.com/acme/widgets/pull/#{number}"
  state["prs"][number.to_s] = { "title" => flag("-t"), "url" => url, "branch" => branch, "state" => "OPEN",
                                "merged_at" => nil, "labels" => [], "checks" => [], "comments" => [] }
  save(state)
  puts url
in ["pr", "edit"]
  pr = pr!(state, ARGV[2])
  flags("--add-label").each do |label|
    fail_with("could not add label: '#{label}' not found") unless state["labels"].include?(label)
    pr["labels"] |= [label]
  end
  flags("--remove-label").each { |label| pr["labels"].delete(label) }
  save(state)
in ["pr", "comment"]
  pr = pr!(state, ARGV[2])
  pr["comments"] << { "author" => { "login" => "openlanes" }, "body" => flag("--body"), "url" => "#{pr["url"]}#issuecomment-#{pr["comments"].size + 1}" }
  save(state)
in ["pr", "view"]
  pr = pr!(state, ARGV[2])
  fields = flag("--json").split(",")
  data = row(ARGV[2][/(\d+)\z/, 1], pr).merge("comments" => pr["comments"], "reviews" => [])
  puts JSON.generate(data.slice(*fields))
in ["pr", "checks"]
  checks = pr!(state, ARGV[2])["checks"]
  fail_with("no checks reported on the '#{pr!(state, ARGV[2])["branch"]}' branch") if checks.empty?
  puts JSON.generate(checks)
  exit 1 if checks.any? { it["bucket"] == "fail" }
  exit 8 if checks.any? { it["bucket"] == "pending" }
in ["pr", "merge"]
  pr = pr!(state, ARGV[2])
  fail_with("Pull request #{pr["url"]} is not mergeable: #{pr["unmergeable"]}") if pr["unmergeable"]
  head = flag("--match-head-commit")
  fail_with("Head branch was modified. Review and try the merge again.") if head && head != pr.fetch("head", "c0ffee#{ARGV[2].to_i}")
  pr["state"] = "MERGED"
  pr["merged_at"] = "2026-10-20T12:00:00Z"
  pr["merge_commit"] ||= "5feedface#{ARGV[2].to_i}"
  save(state)
in ["pr", "update-branch"]
  pr = pr!(state, ARGV[2])
  fail_with("Cannot update PR branch due to conflicts") if pr["conflicts"]
  pr["checks"] = []
  save(state)
in ["api", %r{/commits/[^/]+/check-runs\z}]
  green = [{ "name" => "ci", "status" => "completed", "conclusion" => "success" }]
  puts JSON.generate("check_runs" => state.fetch("main_checks", green))
in ["api", %r{/commits/[^/]+/status\z}]
  puts JSON.generate("statuses" => state.fetch("main_statuses", []))
in ["pr", "list"]
  head = flag("--head")
  wanted = flag("--state")
  rows = state["prs"].select { |_, pr| head.nil? || pr["branch"] == head }
  rows = rows.select { |_, pr| pr["state"] == "MERGED" } if wanted == "merged"
  puts JSON.generate(rows.map { |number, pr| row(number, pr) })
else
  fail_with("fake gh: no answer for gh #{ARGV.join(" ")}", 2)
end
# rubocop:enable RSpec/Output
