# frozen_string_literal: true

%w[digest fileutils json time tmpdir].each { require it }

module OpenLanes
  module Plans
    class PlanState
      # The store under every {PlanState} section. A write locks, re-reads,
      # changes, and renames a temp file over the old one, so two agents
      # signing in one second cannot lose each other's line, and a reader never
      # sees half a file. The lock is in the temp dir, keyed by the plan's
      # number, because the folder it protects is renamed as the plan moves.
      class Document
        # @param text [String, nil]
        # @return [Time] the epoch for text that is not a time
        def self.parse_time(text)
          Time.iso8601(text.to_s)
        rescue ArgumentError
          Time.at(0)
        end

        # @param dir [String] a plan folder
        def initialize(dir:)
          @dir = dir
        end

        # @return [String]
        attr_reader :dir

        # @return [String]
        def path = File.join(dir, FILENAME)

        # @return [Boolean]
        def exist? = File.file?(path)

        # @return [Hash] the whole document, or a fresh one when there is none yet
        def read
          return skeleton unless exist?

          data = JSON.parse(File.read(path, encoding: "UTF-8"))
          data.is_a?(Hash) ? skeleton.merge(data) : skeleton
        rescue JSON::ParserError => e
          raise Error, "#{path} is not valid JSON: #{e.message.lines.first.strip}"
        end

        # @yieldparam data [Hash] mutate in place, under the lock
        # @return [Hash] what was written
        def update
          locked do
            data = read
            yield data
            data["plan"] = identity
            data["updated_at"] = Time.now.iso8601
            write(data)
            data
          end
        end

        # @return [Hash] the plan's number and slug, from its folder name right now
        def identity
          feature = Feature.parse(dir)
          feature ? { "ordinal" => feature.ordinal.to_s, "slug" => feature.slug } : { "ordinal" => nil, "slug" => File.basename(dir) }
        end

        private

        # @return [Hash]
        def skeleton
          { "$schema" => SCHEMA_ID, "version" => VERSION, "plan" => identity, "state" => nil,
            "updated_at" => nil, "stages" => [], "signatures" => [], "messages" => [] }
        end

        # @param data [Hash]
        # @return [void]
        def write(data)
          tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
          File.write(tmp, "#{JSON.pretty_generate(data)}\n")
          File.rename(tmp, path)
        ensure
          FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
        end

        # @return [Object] the block's value
        def locked
          lock = File.join(Dir.tmpdir, "openlanes-plan-#{lock_key}.lock")
          File.open(lock, File::RDWR | File::CREAT, 0o644) do |f|
            f.flock(File::LOCK_EX)
            yield
          end
        end

        # @return [String] the plans directory and the plan's number, stable while the folder is renamed
        def lock_key
          plans = File.expand_path(File.dirname(dir))
          Digest::SHA256.hexdigest("#{plans}\0#{identity["ordinal"] || File.basename(dir)}")[0, 16]
        end
      end
    end
  end
end
