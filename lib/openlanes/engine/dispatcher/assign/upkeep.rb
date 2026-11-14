# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # The tree put right before anyone is assigned: folder names
        # reconciled with their contents, `starts:` lanes fast-forwarded, and
        # blocked plans aged.
        class Upkeep < Step
          # A folder's name can lag its contents: a run killed before its
          # rename, a plan.md written by hand, a resync nobody ran. So the
          # names are reconciled before every dispatch, the way `resync dirs`
          # would, and a ⚪ folder that already holds a plan goes to the pair
          # under its honest name. Plans an agent is working in right now are
          # left alone: the prompt names the folder by path, and moving it
          # under a running agent would strand every write it makes. Nor is a
          # plan another machine holds touched. Then the blocked plans age
          # (plan 009), so a 💣 is in place before anyone is assigned.
          #
          # @return [void]
          def reconcile
            busy = untouchable
            Lifecycle::Resync::Dirs.new(tree: runner.tree.reload, except: busy).call(commit: !runner.dry_run?)
            fast_forward(busy) unless runner.dry_run?
            runner.age!(except: busy)
          end

          private

          # Plans whose `starts:` skips research, rewriting or planning are
          # moved past those phases before anyone is assigned.
          #
          # @param busy [Array<String>] ordinals an agent is working right now
          # @return [void]
          def fast_forward(busy)
            runner.in_scope.each { |subject| advance(subject) unless busy.include?(subject.feature.ordinal.to_s) }
          end

          # More than one hop in a tick: a plan already at 📋 with a `building`
          # spec still goes on to ⭐, since no agent works it in between and a
          # run could otherwise settle at 📋 with the builder never asked.
          def advance(subject)
            Plans::StateMachine::SPINE.size.times do
              moved = Lifecycle::Lanes.advance(subject, commit: true) or break
              UI.log("starts: #{moved.first} -> #{moved.last}", plan: subject.feature.ordinal.to_s)
              subject = Plans::Tree.new(dir: runner.tree.dir).find(subject.feature.ordinal) or break
            end
          end
        end
      end
    end
  end
end
