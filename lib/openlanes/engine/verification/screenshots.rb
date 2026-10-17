# frozen_string_literal: true

require "fileutils"
require "open3"

module OpenLanes
  module Engine
    module Verification
      # The images one round leaves, made ready to commit (M14): PNG only,
      # only the failing step and the final state, each optimised.
      #
      # PNG because GitHub renders neither AVIF nor WebP inline in a pull
      # request comment, and a screenshot nobody sees proves nothing. Two
      # images because every one lands in the branch, then on `main`, for
      # good: a plan rejected three times already adds six.
      class Screenshots
        # Anything an image could be. Only `.png` survives {#prepare}.
        IMAGE = /\.(?:png|jpe?g|gif|webp|avif|heic|heif|bmp|tiff?)\z/i

        # The last screenshot of every round, pass or fail.
        FINAL = "final.png"

        # Optimisers, in the order tried (M14 names both). Each writes a
        # recompressed copy; the smallest file, the original included, is
        # the one kept, so an optimiser that grows an already tight PNG (vips
        # does, on small flat images) costs nothing.
        TOOLS = {
          "vips"   => ->(from, to) { ["vips", "pngsave", from, to, "--compression", "9", "--keep", "none"] },
          "magick" => ->(from, to) { ["magick", from, "-strip", "-define", "png:compression-level=9", to] }
        }.freeze

        # A round holding an image other than PNG.
        class Refused < Error; end

        # @param dir [String] the round's folder
        # @param tools [Hash{String => Proc}] name to argv builder, see {TOOLS}
        # @param which [#call] a tool name to whether it is on `PATH`
        # @param runner [#call] argv to whether it succeeded
        def initialize(dir:, tools: TOOLS, which: method(:on_path?), runner: method(:run))
          @dir = dir
          @tools = tools
          @which = which
          @runner = runner
        end

        # Refuse what is not PNG, drop every image but the failing step's and
        # {FINAL}, and optimise those.
        #
        # @param failing_step [Integer, nil] the step whose screenshot to keep
        # @return [Array<String>] the kept paths, failing step first
        # @raise [Refused] naming every image that is not PNG; nothing is deleted then
        def prepare(failing_step: nil)
          images = Dir.children(@dir).select { it.match?(IMAGE) && File.file?(File.join(@dir, it)) }.sort
          foreign = images.grep_v(/\.png\z/i)
          raise Refused, "#{@dir}: not PNG, which GitHub does not show inline: #{foreign.join(", ")}" unless foreign.empty?

          keep = [(format(Report::STEP_PNG, failing_step) if failing_step), FINAL].compact
          (images - keep).each { FileUtils.rm_f(File.join(@dir, it)) }
          kept = keep.map { File.join(@dir, it) }.select { File.file?(it) }
          optimise(kept)
          kept
        end

        private

        # @param paths [Array<String>]
        # @return [void]
        def optimise(paths)
          return if paths.empty?

          available = @tools.select { |name, _| @which.call(name) }
          if available.empty?
            UI.log("screenshots not optimised: neither #{@tools.keys.join(" nor ")} is installed", level: :warn)
            return
          end

          paths.each { |path| shrink(path, available.values) }
        end

        # @return [void]
        def shrink(path, builders)
          candidates = builders.each_with_index.filter_map do |build, i|
            out = "#{path}.#{i}.tmp.png"
            @runner.call(build.call(path, out)) && File.file?(out) ? out : nil
          end
          best = candidates.min_by { File.size(it) }
          FileUtils.mv(best, path) if best && File.size(best) < File.size(path)
        ensure
          candidates&.each { FileUtils.rm_f(it) }
        end

        # @param name [String]
        # @return [Boolean]
        def on_path?(name) = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, name)) }

        # @param argv [Array<String>]
        # @return [Boolean]
        def run(argv)
          _, status = Open3.capture2e(*argv)
          status.success?
        rescue SystemCallError
          false
        end
      end
    end
  end
end
