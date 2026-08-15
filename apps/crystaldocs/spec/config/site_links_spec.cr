require "../spec_helper"

# SiteLinks is copied byte-identical into every app's config/, so this spec
# is the same in all four: it exercises the shared mechanism, not anything
# app-specific. See config/site_links.cr for why it is a Hash rather than a
# NamedTuple, and why it is required unconditionally at boot in production.

private ENV_KEYS = {
  :crystalshards => "SHARDS_SITE_ORIGIN",
  :crystaldocs   => "DOCS_SITE_ORIGIN",
  :crystalgigs   => "GIGS_SITE_ORIGIN",
  :crystalbits   => "BITS_SITE_ORIGIN",
} of Symbol => String

# Runs the block with every one of the four site-origin variables at its
# spec_helper default, except `site`, which is set to `value` (or cleared
# when `value` is nil so a spec can assert what happens when it is absent).
# Restores every variable it touched afterward, whatever happens.
private def with_origin(site : Symbol, value : String?, &)
  key = ENV_KEYS[site]
  previous = ENV[key]?

  if value
    ENV[key] = value
  else
    ENV.delete(key)
  end

  begin
    yield
  ensure
    if previous
      ENV[key] = previous
    else
      ENV.delete(key)
    end
  end
end

describe SiteLinks do
  describe ".origin" do
    it "comes from configuration" do
      with_origin(:crystalgigs, "https://gigs.example.test") do
        SiteLinks.origin(:crystalgigs).should eq("https://gigs.example.test")
      end
    end

    # A trailing slash in the variable would otherwise produce a double slash
    # in every footer link, which resolves but is not the canonical URL.
    it "does not double the separator when the origin has a trailing slash" do
      with_origin(:crystalbits, "https://bits.example.test/") do
        SiteLinks.origin(:crystalbits).should eq("https://bits.example.test")
      end
    end

    # No default, in any environment, for any of the four. A guess about
    # where a sibling site lives produces a link that resolves somewhere
    # real, which is the failure nobody notices; a startup error naming the
    # variable is the one they do.
    it "refuses to guess when it is unset, naming the variable" do
      with_origin(:crystaldocs, nil) do
        message = expect_raises(SiteLinks::MissingOrigin) do
          SiteLinks.origin(:crystaldocs)
        end.message.to_s

        message.should contain("DOCS_SITE_ORIGIN")
      end
    end

    it "refuses a blank value the same way" do
      with_origin(:crystalshards, "   ") do
        expect_raises(SiteLinks::MissingOrigin) do
          SiteLinks.origin(:crystalshards)
        end
      end
    end

    # The production incident CrystalShards::DocsSite already guards against
    # for one origin: terraform composing a scheme onto a value that was
    # already a full origin, which resolves as valid-looking and clickable
    # while going nowhere real.
    it "refuses a doubled scheme rather than rendering it into a footer link" do
      with_origin(:crystalgigs, "https://https://crystalgigs.com") do
        message = expect_raises(SiteLinks::MalformedOrigin) do
          SiteLinks.origin(:crystalgigs)
        end.message.to_s

        message.should contain("GIGS_SITE_ORIGIN")
      end
    end

    it "refuses a bare hostname with no scheme" do
      with_origin(:crystalbits, "crystalbits.org") do
        expect_raises(SiteLinks::MalformedOrigin) do
          SiteLinks.origin(:crystalbits)
        end
      end
    end

    # A path would be silently prepended to every footer link.
    it "refuses an origin carrying a path" do
      with_origin(:crystalshards, "https://crystalshards.org/shards") do
        expect_raises(SiteLinks::MalformedOrigin) do
          SiteLinks.origin(:crystalshards)
        end
      end
    end

    it "raises ArgumentError for a site it does not know about" do
      expect_raises(ArgumentError) do
        SiteLinks.origin(:crystalnotasite)
      end
    end
  end

  describe ".others" do
    it "excludes the caller's own site and includes the other three" do
      SiteLinks.others(than: :crystaldocs).should_not contain(:crystaldocs)
      SiteLinks.others(than: :crystaldocs).size.should eq(3)
    end

    it "lists the other three in SITES' declared order" do
      SiteLinks.others(than: :crystalbits).should eq([:crystalshards, :crystaldocs, :crystalgigs])
    end
  end

  describe ".require!" do
    # This is the exact call `config/site_links.cr` makes unconditionally
    # when LuckyEnv.production?: a missing or malformed origin for ANY of
    # the four sites has to stop that call, naming the variable, rather than
    # let the app boot and hand a reader a footer link to nowhere.
    it "raises on the first missing origin, naming its variable" do
      with_origin(:crystalgigs, nil) do
        message = expect_raises(SiteLinks::MissingOrigin) do
          SiteLinks.require!
        end.message.to_s

        message.should contain("GIGS_SITE_ORIGIN")
      end
    end

    it "raises on a malformed origin the same way" do
      with_origin(:crystaldocs, "https://https://crystaldocs.org") do
        expect_raises(SiteLinks::MalformedOrigin) do
          SiteLinks.require!
        end
      end
    end

    it "passes when every origin is configured" do
      SiteLinks.require!
    end
  end
end
