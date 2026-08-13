require "../spec_helper"

private def with_unresolved_packages(&)
  CrystalStorage.packages = nil
  yield
ensure
  CrystalStorage.packages = nil
end

describe CrystalShards::StorageService do
  it "publishes documentation without resolving the unrelated packages bucket" do
    path = File.tempname("storage_service_docs", ".json")
    File.write(path, %({"program":{"name":"docs-only"}}))

    with_unresolved_packages do
      with_env("LUCKY_ENV", "production") do
        with_env(CrystalStorage::Buckets::PACKAGES_ENV, nil) do
          docs = FakeObjectStore.new
          key = CrystalShards::StorageService.new(docs: docs).upload_docs_json(
            "github.com/user/docs-only",
            "1.0.0",
            path
          )

          key.should eq("github.com/user/docs-only/1.0.0/docs.json")
          String.new(docs.objects[key]).should eq(%({"program":{"name":"docs-only"}}))
        end
      end
    end
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "still requires the packages bucket when package storage is first used" do
    with_unresolved_packages do
      with_env("LUCKY_ENV", "production") do
        with_env(CrystalStorage::Buckets::PACKAGES_ENV, nil) do
          service = CrystalShards::StorageService.new(docs: FakeObjectStore.new)

          expect_raises(CrystalStorage::MissingBucket, /PACKAGES_BUCKET/) do
            service.package_download_url("github.com/user/package", "1.0.0")
          end
        end
      end
    end
  end
end
