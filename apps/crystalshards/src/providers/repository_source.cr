require "./host_text"
require "./repository_snapshot"

# What indexing needs from a host, independent of which host it is.
#
# Two implementations. GithubRepositoryApi talks to GitHub's REST API and can
# enumerate tags, which is what makes a version dropdown possible. Everything
# else goes through ProviderRepositorySource, which composes the BaseProvider
# methods every host already implements and reports the default branch as its
# one ref.
#
# That split is a real difference in what the hosts give us, not a shortcut:
# a GitLab or Bitbucket shard still gets stars, a description, a licence, a
# parsed manifest, dependency edges and a README. What it does not yet get is a
# list of tags, and it is recorded as having one branch-sourced version rather
# than being skipped or left looking versionless.
abstract class RepositorySource
  # A file at a ref, with absence distinguished from failure.
  #
  # `Absent` is a fact about the repository: this tag really has no shard.yml,
  # and that gets recorded on the version so a reader knows why the page is
  # thin. `Failed` is a fact about the fetch and is retried on a later pass.
  # Collapsing both to nil is what left the old provider unable to tell a
  # library with no manifest from a host having a bad second.
  #
  # A namespace module rather than an abstract struct with three subtypes, and
  # the difference is load-bearing. Under a common ancestor Crystal normalises
  # `Found | Absent | Failed` to that ancestor's virtual type, so a `case ... in`
  # over the union reports the abstract parent as an unhandled case and can
  # never be satisfied. Three unrelated structs in a module stay three types,
  # the union stays a union, and exhaustiveness means what it says.
  module FileResult
    struct Found
      getter content : String

      # Scrubbed on the way in, so no caller has to remember that a file from
      # a host may carry a byte Postgres cannot store. See HostText.
      def initialize(content : String)
        @content = HostText.scrub(content)
      end
    end

    struct Absent
    end

    struct Failed
      getter reason : String

      def initialize(@reason : String)
      end
    end
  end

  # The three concrete results, as a union.
  #
  # `fetch_file` is restricted to this rather than to the abstract parent so a
  # `case ... in` over it is genuinely exhaustive. Restricted to `FileResult`
  # the compiler cannot see past the abstract type, every caller has to carry a
  # branch for a value that can never exist, and the exhaustiveness check stops
  # meaning anything. This way a fourth outcome added here breaks every caller
  # that has not handled it, which is the entire point of matching with `in`.
  #
  # Named FileOutcome rather than File on purpose: `File` is a stdlib class, and
  # an alias that shadows one inside a class body is a name two readers will
  # resolve differently.
  alias FileOutcome = FileResult::Found | FileResult::Absent | FileResult::Failed

  # The repository is gone, renamed, or private to this credential. A final
  # answer: retrying spends quota to be told no again, so the caller marks the
  # row rather than leaving the shard at the head of the queue.
  class NotFound < Exception
  end

  # The host refused or failed. Retryable, so the caller records it and a later
  # pass tries again.
  class Error < Exception
  end

  # Repository facts plus every ref worth indexing, newest-first ordering not
  # assumed. Raises NotFound or Error.
  abstract def fetch_snapshot : RepositorySnapshot

  abstract def fetch_file(ref : String, path : String) : FileOutcome

  # The committed date for one ref, or nil when the host will not cheaply say.
  # Called once per shard, for the version actually being indexed.
  def fetch_commit_date(sha : String) : Time?
    nil
  end
end
