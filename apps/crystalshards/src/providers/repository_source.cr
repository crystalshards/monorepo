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
  abstract struct FileResult
    struct Found < FileResult
      getter content : String

      def initialize(@content : String)
      end
    end

    struct Absent < FileResult
    end

    struct Failed < FileResult
      getter reason : String

      def initialize(@reason : String)
      end
    end
  end

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

  abstract def fetch_file(ref : String, path : String) : FileResult

  # The committed date for one ref, or nil when the host will not cheaply say.
  # Called once per shard, for the version actually being indexed.
  def fetch_commit_date(sha : String) : Time?
    nil
  end
end
