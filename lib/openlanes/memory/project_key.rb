# frozen_string_literal: true

require "open3"
require "uri"

module OpenLanes
  module Memory
    # The key a project is tagged with in the operator's global store (C3):
    # its `origin` remote, normalised, so two clones of one repository count
    # as one project and a lesson does not turn global because the same
    # project was checked out twice. Without a remote, the real path of the
    # root, which is stable for as long as the checkout is.
    #
    # Never a name or an email, and never a credential: userinfo in an
    # `https://user:token@host/...` remote is dropped, since the key is
    # written to disk and printed by `openlanes memory inbox --global`.
    module ProjectKey
      module_function

      # @param root [String] the project root
      # @return [String] e.g. `github.com/example/repo`
      def for(root)
        out, status = Open3.capture2("git", "-C", root, "remote", "get-url", "origin", err: File::NULL)
        (normalise(out) if status.success?) || File.realpath(root)
      rescue SystemCallError
        File.expand_path(root)
      end

      # @param url [String] a git remote, in URL, scp or path form
      # @return [String, nil] `host/path` lower-cased host, no `.git`; nil when empty
      def normalise(url)
        url = url.to_s.strip
        return if url.empty?

        host, path = split(url)
        key = [host&.downcase, path.sub(%r{/+\z}, "").delete_suffix(".git").sub(%r{\A/+}, "")].compact.join("/")
        host ? key : "/#{key}"
      end

      # @return [Array(String, String)] host (nil for a local path) and path
      def split(url)
        if url.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
          uri = URI.parse(url)
          [uri.host, uri.path]
        elsif (scp = url.match(%r{\A(?:[^@/]+@)?([^:/]+):(.+)\z}))
          [scp[1], scp[2]]
        else
          [nil, File.expand_path(url)]
        end
      rescue URI::InvalidURIError
        [nil, url]
      end
      private_class_method :split
    end
  end
end
