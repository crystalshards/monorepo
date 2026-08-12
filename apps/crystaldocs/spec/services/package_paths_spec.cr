require "../spec_helper"

# The URL shape, which two apps and every page on this one have to agree on.
describe CrystalDocs::PackagePaths do
  describe "a host qualified key" do
    it "nests under the static segment, so it cannot be read as a package name" do
      CrystalDocs::PackagePaths.package_path("github.com/kemalcr/kemal")
        .should eq("/docs/_/github.com/kemalcr/kemal")
    end

    it "carries the version after the repository" do
      CrystalDocs::PackagePaths.version_path("github.com/kemalcr/kemal", "1.6.0")
        .should eq("/docs/_/github.com/kemalcr/kemal/1.6.0")
    end

    it "carries a type path after the version" do
      CrystalDocs::PackagePaths.type_path("github.com/kemalcr/kemal", "1.6.0", "Kemal/Config")
        .should eq("/docs/_/github.com/kemalcr/kemal/1.6.0/Kemal/Config")
    end
  end

  # These URLs are live and indexed, so their shape is not ours to change.
  describe "a bare key" do
    it "keeps the URL it has always had" do
      CrystalDocs::PackagePaths.package_path("crystal").should eq("/docs/crystal")
      CrystalDocs::PackagePaths.version_path("crystal", "1.21.0").should eq("/docs/crystal/1.21.0")
      CrystalDocs::PackagePaths.type_path("crystal", "1.21.0", "String")
        .should eq("/docs/crystal/1.21.0/String")
    end
  end

  # The separator is the whole discriminator, in both apps and in the router.
  describe "telling the two apart" do
    it "reads a key with separators as a repository" do
      CrystalDocs::PackagePaths.canonical?("github.com/kemalcr/kemal").should be_true
    end

    it "reads a key without them as a name" do
      CrystalDocs::PackagePaths.canonical?("kemal").should be_false
    end
  end
end
