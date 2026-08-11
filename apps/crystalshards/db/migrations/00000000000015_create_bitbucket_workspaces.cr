# The list of Bitbucket workspaces discovery is allowed to enumerate.
#
# This table exists because Bitbucket has no global enumeration to crawl.
# `GET /2.0/repositories`, the firehose the other hosts' equivalents provide,
# answers 410 Gone with "CHANGE-2770 - Functionality has been deprecated", and
# `GET /2.0/workspaces` answers 401 and only ever lists workspaces the token is
# already a member of. There is no query that reaches a stranger's repository.
#
# So the owner tells us where to look, one workspace at a time, and coverage of
# bitbucket.org is defined by the rows in here rather than by the host. Nothing
# secret lives in this table: the app password is configuration, read from the
# environment, and the crawl cursor lives on crawl_states with every other
# host's.
class CreateBitbucketWorkspaces::V00000000000015 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(BitbucketWorkspace) do
      primary_key id : Int64
      add_timestamps
      # The workspace's slug as it appears in the API path and in
      # bitbucket.org/<slug>. Unique because registering one twice would
      # enumerate it twice in a single pass and inflate the counts.
      add slug : String, unique: true, index: true
      # A workspace that has gone private, been renamed or turned out to hold
      # nothing is disabled rather than deleted, so the reason survives and the
      # sweep stops paying for it.
      add enabled : Bool, default: true
      add note : String?
      # Filled in by the sweep, so an operator can see which registered
      # workspaces are actually answering.
      add last_seen_at : Time?
      add last_error : String?
      add repository_count : Int32, default: 0
    end
  end

  def rollback
    drop table_for(BitbucketWorkspace)
  end
end
