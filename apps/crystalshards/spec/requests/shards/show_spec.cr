require "../../spec_helper"

describe Shards::Show do
  describe "basic rendering" do
    it "renders HTML successfully for valid shard" do
      shard = ShardFactory.create &.name("test-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("text/html")
    end

    it "returns 404 for non-existent shard" do
      # The action raises RouteNotFoundError which Lucky converts to 404
      # Since the test framework may handle this differently, we just verify
      # that accessing a non-existent shard doesn't succeed
      begin
        response = BrowserClient.exec(Shards::Show.with(**unregistered_identity))
        # If we get here, verify it's a 404
        response.status_code.should eq(404)
      rescue Lucky::RouteNotFoundError
        # This is the expected behavior - test passes
      end
    end
  end

  describe "shard information display" do
    it "shows shard name" do
      shard = ShardFactory.create &.name("awesome-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("awesome-shard")
    end

    it "shows shard description" do
      shard = ShardFactory.create &.name("test-shard")
        .description("An awesome Crystal library")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("An awesome Crystal library")
    end

    it "shows GitHub repository link" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("https://github.com/user/test-shard")
      response.body.should contain("Repository")
    end

    it "shows homepage link when available" do
      shard = ShardFactory.create &.name("test-shard")
        .homepage_url("https://testshard.com")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("https://testshard.com")
      response.body.should contain("Homepage")
    end

    it "hides homepage link when not available" do
      shard = ShardFactory.create &.name("test-shard")
        .homepage_url(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should_not contain("Homepage")
    end

    # The documentation link is not conditional on documentation existing.
    # crystaldocs builds a release the first time somebody asks for it, so
    # arriving is what causes the documentation to exist; a link that waited
    # for a build would wait forever.
    it "links to the shard's documentation whether or not any has been built" do
      shard = ShardFactory.create &.name("test-shard")
        .documentation_url(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain(CrystalShards::DocsSite.url_for?(shard).not_nil!)
      response.body.should contain("Read the API docs")
    end

    # No version in the link: crystaldocs holds the release list and picks the
    # current one, so this cannot go stale the next time a maintainer tags.
    it "links to the repository rather than to a version" do
      shard = ShardFactory.create &.name("test-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      docs = CrystalShards::DocsSite.origin
      response.body.should contain("#{docs}/docs/_/#{shard.canonical_slug}\"")
    end

    it "shows the maintainer's own documentation link alongside it" do
      shard = ShardFactory.create &.name("test-shard")
        .documentation_url("https://docs.testshard.com")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("https://docs.testshard.com")
      response.body.should contain("The maintainer also publishes")
    end

    it "claims no maintainer link when the maintainer declared none" do
      shard = ShardFactory.create &.name("test-shard")
        .documentation_url(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should_not contain("The maintainer also publishes")
    end

    it "shows license information" do
      shard = ShardFactory.create &.name("test-shard")
        .license("MIT")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("License:")
      response.body.should contain("MIT")
    end

    it "shows GitHub stars" do
      shard = ShardFactory.create &.name("test-shard")
        .github_stars(42)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      # Assert on the count and its visible unit, not on an icon glyph: the
      # star is decorative and aria-hidden, so it carries no meaning.
      response.body.should contain("42")
      response.body.should contain("stars")
    end

    # Stars come from a fetch against the host that may not have happened, so
    # nil means unknown. Hiding it would make the majority of pages in this
    # registry show no star row at all, which is indistinguishable from a
    # render that broke.
    it "says stars are not indexed rather than hiding the figure" do
      shard = ShardFactory.create &.name("test-shard")
        .github_stars(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("stars")
      response.body.should contain("not indexed")
    end

    it "shows a fetched zero as zero, which is not the same as unknown" do
      shard = ShardFactory.create &.name("test-shard")
        .github_stars(0)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("<strong>0</strong>")
      response.body.should contain("stars")
    end

    # Nothing is downloaded from this registry: `shards` fetches from the
    # origin repository. A download figure here could only ever be zero, and a
    # permanent zero reads as "nobody uses this", so it is absent rather than
    # shown.
    it "renders no downloads figure at all" do
      shard = ShardFactory.create &.name("test-shard")
        .total_downloads(1234)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should_not contain("downloads")
      response.body.should_not contain("1234")
    end

    # Dependents are counted in our own tables, so unlike stars they can never
    # be unknown and a zero is always the truth.
    it "always shows a dependent count, zero included" do
      shard = ShardFactory.create &.name("test-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("dependents")
      response.body.should contain("No indexed shard depends on this one yet.")
    end

    it "counts and names the shards that depend on this one" do
      target = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")
      depender = ShardFactory.create &.name("my-app").at("github.com", "someone", "my-app")
      version = ShardVersionFactory.create &.shard_id(depender.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("kemal")
        .dependent_shard_id(target.id)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(target)))

      response.body.should contain("<strong>1</strong>")
      response.body.should contain(" dependent")
      response.body.should contain("my-app")
      response.body.should contain("/shards/github.com/someone/my-app")
    end

    it "names the repository the shard comes from" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://gitlab.com/acme/test-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Repository")
      response.body.should contain("gitlab.com/acme/test-shard")
    end
  end

  describe "version display" do
    it "shows latest version number" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.2.3")
        .released_at(Time.utc)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("1.2.3")
    end

    it "lists all versions" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(3.days.ago)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.1.0")
        .released_at(2.days.ago)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.2.0")
        .released_at(1.day.ago)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("1.0.0")
      response.body.should contain("1.1.0")
      response.body.should contain("1.2.0")
      response.body.should contain("Versions")
    end

    # The picker is the release history, so it is not truncated. A shard with
    # a hundred releases scrolls; a shard whose older releases were hidden
    # behind "and 5 more..." gave a reader no way to reach them at all.
    it "lists every version in the picker rather than truncating" do
      shard = ShardFactory.create &.name("test-shard")
      15.times do |i|
        ShardVersionFactory.create &.shard_id(shard.id)
          .version("1.#{i}.0")
          .released_at(Time.utc - i.days)
      end

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      15.times do |i|
        response.body.should contain("1.#{i}.0")
      end
      response.body.should contain("15 versions")
      response.body.should_not contain("more...")
    end

    it "shows version release dates" do
      shard = ShardFactory.create &.name("test-shard")
      release_time = Time.utc(2024, 1, 15)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(release_time)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Jan 15, 2024")
    end

    it "marks a yanked version in the picker" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .yanked(true)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("badge-yanked")
      response.body.should contain("yanked")
      response.body.should contain("should not be picked for new work")
    end

    # A shard with no tags is the normal case in this registry, not an error,
    # so the absence is a sentence rather than a missing control.
    it "states that no releases are tagged instead of showing an empty picker" do
      shard = ShardFactory.create &.name("test-shard").indexed_at(Time.utc)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.body.should contain("No tagged releases")
      response.body.should contain("resolves a version from a git tag")
      response.body.should_not contain("version-picker-list")
    end

    it "orders versions by most recent first" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(Time.utc(2024, 6, 1))

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      version_2_position = response.body.index("2.0.0")
      version_1_position = response.body.index("1.0.0")

      version_2_position.should_not be_nil
      version_1_position.should_not be_nil
      version_2_position.not_nil!.should be < version_1_position.not_nil!
    end
  end

  describe "installation instructions" do
    it "shows shard.yml snippet with correct syntax" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("# Add this to your shard.yml")
      response.body.should contain("dependencies:")
      response.body.should contain("test-shard:")
      response.body.should contain("github: user/test-shard")
      # HTML encodes '>' as '&gt;'
      response.body.should contain("version: ~&gt; 1.0.0")
    end

    it "shows shards install command" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Then run:")
      response.body.should contain("shards install")
    end

    it "uses latest version in installation instructions" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(2.days.ago)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(1.day.ago)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      # HTML encodes '>' as '&gt;'
      response.body.should contain("version: ~&gt; 2.0.0")
      response.body.should_not contain("version: ~&gt; 1.0.0")
    end

    it "extracts correct GitHub path from repository URL" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/crystal-lang/awesome-shard.git")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("github: crystal-lang/awesome-shard")
      # Note: .git still appears in the repository link, but not in the github: path
      # The github: path correctly strips .git
    end

    it "handles repository URLs without .git suffix" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("github: user/test-shard")
    end

    # An untagged repository can still be depended on, so the snippet is still
    # correct and still shown. What changes is what it pins to: a branch
    # rather than a version. Withholding the snippet taught a reader nothing
    # and left them with a page that had a heading and no content.
    it "shows a branch-tracking snippet when no versions exist" do
      shard = ShardFactory.create &.name("test-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Installation")
      response.body.should contain("# Add this to your shard.yml")
      response.body.should contain("shards install")
      response.body.should contain("No release to pin to")
      response.body.should_not contain("version: ~&gt;")
    end
  end

  describe "dependencies" do
    it "lists runtime dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("http-client")
        .version_requirement("~> 1.0")
        .scope("runtime")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Dependencies")
      response.body.should contain("http-client")
      # HTML encodes '>' as '&gt;'
      response.body.should contain("~&gt; 1.0")
    end

    it "shows dependency version requirements" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("json-lib")
        .version_requirement(">= 2.0, < 3.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      # HTML encodes '>' and '<' as '&gt;' and '&lt;'
      response.body.should contain("&gt;= 2.0, &lt; 3.0")
    end

    it "distinguishes development dependencies with badge" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("spec-helper")
        .scope("development")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      # Development dependencies ARE shown with a dev badge
      response.body.should contain("spec-helper")
      response.body.should contain("badge-dev")
      response.body.should contain("Development Dependencies")
    end

    it "does not show dev badge for runtime dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("runtime-lib")
        .scope("runtime")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("runtime-lib")
      response.body.should_not contain("badge-dev")
    end

    # "This version declares no dependencies" is a fact a reader came for. An
    # omitted section is indistinguishable from one that failed to load, which
    # is the whole class of bug being fixed here.
    it "states that an indexed version declares no dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      # indexed_at is what the indexer stamps and what indexed? now reads.
      # Metadata alone no longer means the manifest was read: a tag with no
      # shard.yml is indexed and empty, which is a fact, not a gap.
      ShardVersionFactory.create &.shard_id(shard.id)
        .indexed_at(Time.utc)
        .metadata(JSON.parse(%({"name": "test-shard", "version": "1.0.0"})))

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.body.should contain("Dependencies")
      response.body.should contain("This version declares no dependencies.")
    end

    # Unknown and none are different answers and the page gives different
    # ones. A version whose shard.yml has never been read has an unknown
    # dependency list, not an empty one.
    it "distinguishes an unread manifest from a version with no dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Dependencies")
      response.body.should contain("has not been read yet")
      response.body.should_not contain("declares no dependencies")
    end

    it "shows multiple dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("dep-one")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("dep-two")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("dep-three")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("dep-one")
      response.body.should contain("dep-two")
      response.body.should contain("dep-three")
    end

    it "only shows dependencies for latest version" do
      shard = ShardFactory.create &.name("test-shard")
      old_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(2.days.ago)
      new_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(1.day.ago)

      DependencyFactory.create &.shard_version_id(old_version.id)
        .name("old-dep")
      DependencyFactory.create &.shard_version_id(new_version.id)
        .name("new-dep")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("new-dep")
      response.body.should_not contain("old-dep")
    end

    # A dependency is recorded as a name, and a name no longer identifies a
    # shard. So the link exists exactly when the dependency was resolved to a
    # repository, and the name is plain text when it was not: linking to
    # whichever "http-client" came back first is how somebody installs the
    # wrong dependency.
    it "links a dependency that resolves to a repository" do
      dependency_shard = ShardFactory.create &.name("http-client")
        .repository_url("https://github.com/someone/http-client")

      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("http-client")
        .version_requirement("~> 1.0")
        .scope("runtime")
        .dependent_shard_id(dependency_shard.id)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("<a href=\"/shards/github.com/someone/http-client\"")
      response.body.should contain("class=\"dependency-link\"")
      response.body.should contain("<strong>http-client</strong>")
    end

    it "names an unresolved dependency without linking it anywhere" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("http-client")
        .version_requirement("~> 1.0")
        .scope("runtime")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("<strong>http-client</strong>")
      response.body.should contain("~&gt; 1.0")
      response.body.should_not contain("class=\"dependency-link\"")
    end
  end

  describe "edge cases" do
    it "handles shard with all optional fields missing" do
      shard = ShardFactory.create &.name("minimal-shard")
        .homepage_url(nil)
        .documentation_url(nil)
        .license(nil)
        .github_stars(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.body.should contain("minimal-shard")
    end

    it "renders every section for a shard with no versions and no dependencies" do
      shard = ShardFactory.create &.name("empty-shard").indexed_at(Time.utc)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.body.should contain("empty-shard")
      response.body.should contain("Installation")
      response.body.should contain("shards install")
      response.body.should contain("No tagged releases")
      response.body.should contain("No shard.yml has been indexed")
      response.body.should contain("No README has been indexed")
      # No version selected, so there is no dependency list to be right or
      # wrong about, and the section is not drawn empty.
      response.body.should_not contain("<h2>Dependencies</h2>")
    end

    it "handles very long shard names" do
      long_name = "a" * 100
      shard = ShardFactory.create &.name(long_name)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.body.should contain(long_name)
    end

    it "handles very long descriptions" do
      long_description = "This is a very long description. " * 50
      shard = ShardFactory.create &.name("test-shard")
        .description(long_description)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.status_code.should eq(200)
      response.body.should contain(long_description)
    end

    it "says a licence is not declared rather than leaving the row blank" do
      shard = ShardFactory.create &.name("test-shard")
        .license(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("License:")
      response.body.should contain("not declared")
    end

    it "says a description is missing rather than leaving a gap under the title" do
      shard = ShardFactory.create &.name("test-shard")
        .description(nil)

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("No description declared in shard.yml.")
    end
  end

  describe "README rendering" do
    it "renders markdown headings and lists as elements rather than literal text" do
      shard = ShardFactory.create &.name("readme-shard")
        .readme_content("# Kemal\n\n- fast\n- simple\n")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("<h1>Kemal</h1>")
      response.body.should contain("<li>fast</li>")
      response.body.should contain("<li>simple</li>")
      response.body.should_not contain("# Kemal")
      response.body.should_not contain("- fast")
    end

    it "renders a fenced code block as pre > code" do
      shard = ShardFactory.create &.name("readme-shard")
        .readme_content(%(```crystal\nputs "hi"\n```))

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("<pre><code")
      response.body.should contain("</code></pre>")
      response.body.should_not contain("```")
    end

    # Markdown permits raw HTML, so a README is an injection vector unless the
    # rendered output drops it rather than merely escaping it.
    it "never lets a script tag in a README reach the page" do
      shard = ShardFactory.create &.name("readme-shard")
        .readme_content("Intro\n\n<script>alert('readme')</script>\n")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("Intro")
      response.body.should_not contain("<script")
      response.body.should_not contain("alert(")
    end

    it "refuses a javascript: link in a README" do
      shard = ShardFactory.create &.name("readme-shard")
        .readme_content("[click me](javascript:alert(1))")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should_not contain("javascript:")
      response.body.should contain("click me")
    end

    it "resolves a relative README image to the repository's raw content URL" do
      shard = ShardFactory.create &.name("readme-shard")
        .at("github.com", "kemalcr", "kemal")
        .readme_content("![Logo](docs/logo.png)")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain(
        %(src="https://raw.githubusercontent.com/kemalcr/kemal/master/docs/logo.png")
      )
    end

    # A repository is not always tagged "1.6.0"; it is tagged "v1.6.0" and
    # ShardVersion#version normalises that for display. A README image has to
    # resolve against the ref that actually exists on the host or the URL
    # this page builds 404s on a repository the maintainer tagged normally.
    it "resolves a README image against the checkout ref, not the display version" do
      shard = ShardFactory.create &.name("readme-shard")
        .at("github.com", "kemalcr", "kemal")
        .readme_content("![Logo](logo.png)")
        .latest_version("1.6.0")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.6.0")
        .ref("v1.6.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain(
        %(src="https://raw.githubusercontent.com/kemalcr/kemal/v1.6.0/logo.png")
      )
      response.body.should_not contain("/1.6.0/logo.png")
    end
  end

  describe "page title" do
    it "uses shard name as page title" do
      shard = ShardFactory.create &.name("awesome-shard")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

      response.body.should contain("<title>")
      response.body.should contain("awesome-shard")
    end
  end
end
