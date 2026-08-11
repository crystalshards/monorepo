# One Bitbucket workspace discovery has been told to enumerate.
#
# Bitbucket is the one host in the registry with no global enumeration behind
# it, so this table is the definition of what "crawling bitbucket.org" covers.
# Adding a row widens coverage; there is no query that would have found the
# workspace on its own.
class BitbucketWorkspace < BaseModel
  # Bitbucket's own rule for a workspace ID, which is also what keeps a slug
  # from escaping the API path it gets interpolated into. Anchored, and checked
  # again by the crawler before the slug is used in a URL, because a validation
  # that only runs on the write path is not a guarantee about the read path.
  SLUG_FORMAT = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9]\z|\A[a-zA-Z0-9]\z/

  def self.valid_slug?(slug : String) : Bool
    slug.matches?(SLUG_FORMAT)
  end

  table do
    column slug : String
    column enabled : Bool
    column note : String?
    column last_seen_at : Time?
    column last_error : String?
    column repository_count : Int32
  end

  def repository_url : String
    "https://bitbucket.org/#{slug}"
  end

  def summary_line : String
    parts = ["#{slug}: #{enabled ? "enabled" : "disabled"}"]
    parts << "#{repository_count} repositories" if repository_count > 0
    parts << "last seen #{last_seen_at}" if last_seen_at
    parts << "error: #{last_error}" if last_error
    parts.join(", ")
  end
end
