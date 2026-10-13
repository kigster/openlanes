# frozen_string_literal: true

require "digest"
require "open3"

module OpenLanes
  module Live
    # The repository a run belongs to, as the part of every key that machines
    # sharing one Redis have in common (W26, W29): `github.com/<owner>/<name>`.
    #
    # Readable rather than hashed, so `redis-cli --scan` shows whose
    # repository a key belongs to. The clone decides which factory a machine
    # joins, and nothing else does, which is why there is no override.
    module Repo
      module_function

      # `git@github.com:Owner/Name.git`, `https://github.com/owner/name`,
      # `ssh://git@github.com/owner/name.git` and their trailing slashes and
      # letter case all fold to one spelling.
      #
      # @param url [String]
      # @return [String, nil] `host/owner/name`, nil for a string that is not
      #   a remote URL
      def normalise(url)
        text = url.to_s.strip.downcase.delete_suffix("/").delete_suffix(".git")
        path = case text
               when %r{\A[a-z][a-z0-9+.-]*://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)\z},
                    %r{\A(?:[^@/]+@)?([^/:]+):(.+)\z} then "#{::Regexp.last_match(1)}/#{::Regexp.last_match(2)}"
               end
        path&.squeeze("/")
      end

      # The repository of the checkout at +root+: its `origin`, normalised,
      # or, with no remote to share, `local/<name>-<12 hex>`, the directory's
      # name and a digest of its real path. The name alone collided: two
      # unrelated clones both called `app` on one Redis would have read each
      # other's boards and taken each other's claims.
      #
      # @param root [String]
      # @return [String]
      def for(root)
        out, status = Open3.capture2("git", "-C", root, "remote", "get-url", "origin", err: File::NULL)
        (status.success? && normalise(out)) || local(root)
      rescue SystemCallError
        local(root)
      end

      # @param root [String]
      # @return [String] `local/<basename>-<12 hex of SHA-256 of the real path>`
      def local(root)
        path = begin
          File.realpath(root)
        rescue SystemCallError
          File.expand_path(root)
        end
        "local/#{File.basename(path)}-#{Digest::SHA256.hexdigest(path)[0, 12]}"
      end
    end
  end
end
