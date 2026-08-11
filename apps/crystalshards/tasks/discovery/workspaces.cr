require "../../src/services/discovery/crawl_runner"

# Manages the Bitbucket workspaces discovery is allowed to enumerate.
#
#   lucky discovery.workspaces                          list them
#   lucky discovery.workspaces --add=acme               register one
#   lucky discovery.workspaces --add=acme --note="..."  register one with a reason
#   lucky discovery.workspaces --disable=acme           stop sweeping it
#   lucky discovery.workspaces --enable=acme            sweep it again
#
# This list is not a convenience. Bitbucket has no global enumeration:
# GET /2.0/repositories answers 410 Gone, so a shard in a workspace nobody has
# registered is not merely unsearched, it is unreachable. Coverage of
# bitbucket.org is exactly what this command prints.
class Discovery::Workspaces < LuckyTask::Task
  summary "List and manage the Bitbucket workspaces discovery enumerates"

  arg :add, "Register a workspace by its Bitbucket id", optional: true
  arg :note, "Why this workspace is registered, stored alongside it", optional: true
  arg :enable, "Re-enable a registered workspace", optional: true
  arg :disable, "Stop sweeping a registered workspace, keeping its row", optional: true

  def call
    if slug = add
      return unless register(slug.strip.downcase)
    end

    if slug = enable
      return unless set_enabled(slug.strip.downcase, true)
    end

    if slug = disable
      return unless set_enabled(slug.strip.downcase, false)
    end

    list
  end

  private def register(slug : String) : Bool
    unless BitbucketWorkspace.valid_slug?(slug)
      puts "#{slug.inspect} is not a Bitbucket workspace id (letters, numbers, hyphens and underscores)."
      return false
    end

    if existing = BitbucketWorkspaceQuery.new.for_slug(slug)
      puts "#{slug} is already registered (#{existing.enabled ? "enabled" : "disabled"})."
      return true
    end

    SaveBitbucketWorkspace.create!(slug: slug, note: note)
    puts "Registered #{slug}. It is swept on the next discovery.backfill --host=bitbucket.org."
    true
  end

  private def set_enabled(slug : String, enabled : Bool) : Bool
    workspace = BitbucketWorkspaceQuery.new.for_slug(slug)

    unless workspace
      puts "#{slug} is not registered."
      return false
    end

    operation = SaveBitbucketWorkspace.new(workspace)
    operation.enabled.value = enabled
    operation.update!
    puts "#{slug} is now #{enabled ? "enabled" : "disabled"}."
    true
  end

  private def list
    workspaces = BitbucketWorkspaceQuery.new.slug.asc_order.results

    puts ""
    if workspaces.empty?
      puts "No Bitbucket workspaces are registered."
      puts "Nothing on bitbucket.org is discovered automatically until at least one is."
    else
      puts "Bitbucket workspaces:"
      workspaces.each { |workspace| puts "  #{workspace.summary_line}" }
    end

    puts ""
    # The boundary travels with the list, so it cannot be read as coverage of
    # the host rather than coverage of these workspaces.
    puts Discovery::CrawlRunner::WORKSPACE_SCOPED["bitbucket.org"] + "."
  end
end
