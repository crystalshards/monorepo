require "../spec_helper"

# Bucket names are deployment facts. Defaulting one in production is the
# failure this guards: an object store with no bucket name does not break in
# any visible way, it writes nowhere and reads back empty, which looks exactly
# like a package that simply has no documentation yet.
private def with_env(values : Hash(String, String?), &)
  original = {} of String => String?
  values.each_key { |key| original[key] = ENV[key]? }

  values.each do |key, value|
    value ? (ENV[key] = value) : ENV.delete(key)
  end

  begin
    yield
  ensure
    original.each do |key, value|
      value ? (ENV[key] = value) : ENV.delete(key)
    end
  end
end

describe CrystalStorage::Buckets do
  describe "in production" do
    it "refuses to resolve a docs bucket that was never named, and says which variable" do
      with_env({"LUCKY_ENV" => "production", "DOCS_BUCKET" => nil}) do
        error = expect_raises(CrystalStorage::MissingBucket) do
          CrystalStorage::Buckets.docs
        end

        # Naming the variable is the entire point. "storage misconfigured"
        # sends someone reading source; this sends them to a deploy setting.
        error.message.to_s.should contain("DOCS_BUCKET")
      end
    end

    it "refuses a packages bucket that was never named, and says which variable" do
      with_env({"LUCKY_ENV" => "production", "PACKAGES_BUCKET" => nil}) do
        error = expect_raises(CrystalStorage::MissingBucket) do
          CrystalStorage::Buckets.packages
        end

        error.message.to_s.should contain("PACKAGES_BUCKET")
      end
    end

    it "treats a blank name as absent rather than as a bucket called empty string" do
      with_env({"LUCKY_ENV" => "production", "DOCS_BUCKET" => "   "}) do
        expect_raises(CrystalStorage::MissingBucket) do
          CrystalStorage::Buckets.docs
        end
      end
    end

    it "uses the configured names when they are present" do
      with_env({
        "LUCKY_ENV"       => "production",
        "DOCS_BUCKET"     => "crystalshards-docs",
        "PACKAGES_BUCKET" => "crystalshards-packages",
      }) do
        CrystalStorage::Buckets.docs.should eq("crystalshards-docs")
        CrystalStorage::Buckets.packages.should eq("crystalshards-packages")
      end
    end

    # CrystalDocs holds no role on the packages bucket, so it is never given
    # that bucket's name. Demanding it at boot would refuse to start over a
    # variable this service has no business knowing, which is a self-inflicted
    # outage on a correct deployment.
    it "requires only the buckets an app asks for" do
      with_env({
        "LUCKY_ENV"       => "production",
        "DOCS_BUCKET"     => "crystalshards-docs",
        "PACKAGES_BUCKET" => nil,
      }) do
        CrystalStorage::Buckets.require!(:docs)
      end
    end
  end

  describe "outside production" do
    # A contributor with no Google Cloud access has to be able to run the app
    # and the specs, so development falls back to what `make services` creates.
    it "falls back to the local bucket names rather than failing" do
      with_env({"LUCKY_ENV" => "development", "DOCS_BUCKET" => nil, "PACKAGES_BUCKET" => nil}) do
        CrystalStorage::Buckets.docs.should eq(CrystalStorage::Buckets::DEV_DOCS)
        CrystalStorage::Buckets.packages.should eq(CrystalStorage::Buckets::DEV_PACKAGES)
      end
    end
  end
end

describe CrystalStorage::Keys do
  # CrystalShards writes these keys and CrystalDocs reads them, across a
  # process boundary, so they are built in one place or they drift.
  it "puts one docs.json per package version" do
    CrystalStorage::Keys.docs_json("kemal", "1.6.0").should eq("kemal/1.6.0/docs.json")
  end

  it "names the published package tarball after its package and version" do
    CrystalStorage::Keys.package("kemal", "1.6.0").should eq("kemal/1.6.0/kemal-1.6.0.tar.gz")
  end
end

describe CrystalStorage::ObjectStore do
  # The build Job holds no credentials, so a signed URL is not a convenience,
  # it is the only way in and out. Refusing anything but GET and PUT keeps a
  # caller from minting a DELETE by passing a string through.
  it "signs only GET and PUT" do
    store = CrystalStorage.docs

    expect_raises(ArgumentError, /GET and PUT/) do
      store.signed_url("anything", method: "DELETE")
    end
  end
end
