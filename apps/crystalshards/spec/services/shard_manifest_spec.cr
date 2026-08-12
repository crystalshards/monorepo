require "../spec_helper"

# Required directly for the same reason the discovery specs do it: src/app.cr
# carries only version_order out of services/, and a manifest parser is not
# something the web app runs.
require "../../src/services/shard_manifest"

# The parser between a repository's shard.yml and a shard's page.
#
# Every case here is a manifest that exists in the wild, and the property under
# test is the same one throughout: parsing must produce either a manifest or a
# sentence, never an exception. A raise here aborts a shard mid-index and costs
# it the rest of its pass, which is how a repository with one bad tag ends up
# with no content at all.
private def parsed(source : String) : ShardManifest
  ShardManifest.parse(source).as(ShardManifest)
end

private def refused(source : String) : String
  ShardManifest.parse(source).as(String)
end

describe ShardManifest do
  describe "a manifest that parses" do
    it "reads the fields a page renders" do
      manifest = parsed(<<-YAML)
        name: kemal
        version: 1.6.0
        crystal: ">= 1.12.0"
        license: MIT
        description: A Lightning Fast, Super Simple web framework
        homepage: https://kemalcr.com
        documentation: https://kemalcr.com/guide
        dependencies:
          radix:
            github: luislavena/radix
            version: ~> 0.4.1
        development_dependencies:
          ameba:
            github: crystal-ameba/ameba
        YAML

      manifest.name.should eq("kemal")
      manifest.version.should eq("1.6.0")
      manifest.crystal.should eq(">= 1.12.0")
      manifest.license.should eq("MIT")
      manifest.description.should eq("A Lightning Fast, Super Simple web framework")
      manifest.homepage.should eq("https://kemalcr.com")
      manifest.documentation.should eq("https://kemalcr.com/guide")

      manifest.dependencies.should_not be_nil
      manifest.dependencies.not_nil!.as_h.keys.should eq(["radix"])
      manifest.development_dependencies.not_nil!.as_h.keys.should eq(["ameba"])
    end

    it "keeps the whole document, which is what dependency resolution reads" do
      manifest = parsed(<<-YAML)
        name: kemal
        dependencies:
          radix:
            github: luislavena/radix
            version: ~> 0.4.1
        YAML

      # `metadata` on the version row is this document verbatim.
      # UpdateDependenciesWorker walks it rather than the typed getters, so a
      # parser that dropped anything it had no getter for would silently stop
      # producing dependency edges.
      manifest.document["dependencies"]["radix"]["github"].as_s
        .should eq("luislavena/radix")
      manifest.document["dependencies"]["radix"]["version"].as_s
        .should eq("~> 0.4.1")
    end

    it "leaves absent fields nil rather than inventing blanks" do
      manifest = parsed("name: bare\n")

      manifest.version.should be_nil
      manifest.crystal.should be_nil
      manifest.license.should be_nil
      manifest.description.should be_nil
      manifest.dependencies.should be_nil
      manifest.development_dependencies.should be_nil
    end

    it "treats an empty string field as absent" do
      # A page renders `description` when it is present. An empty string is
      # present and renders as a blank line under the shard's name, which reads
      # as a broken page rather than as a shard that never wrote one.
      manifest = parsed("name: blanks\ndescription: \"\"\nlicense: \"\"\n")

      manifest.description.should be_nil
      manifest.license.should be_nil
    end
  end

  describe "the crystal constraint" do
    it "reads a quoted constraint as written" do
      parsed(%(name: x\ncrystal: ">= 1.0.0"\n)).crystal.should eq(">= 1.0.0")
    end

    it "reads a bare number, which YAML gives us as a float" do
      # `crystal: 0.35` is not a string in YAML. Rendering the float back would
      # print 0.35 as 0.35000000000000003 on a version badge.
      parsed("name: x\ncrystal: 0.35\n").crystal.should eq("0.35")
    end

    it "renders a whole-number constraint without a decimal point" do
      # `crystal: 1` is a float to YAML too, and "1.0" is a different claim
      # from the one the manifest made.
      parsed("name: x\ncrystal: 1\n").crystal.should eq("1")
    end
  end

  describe "app-versus-library facts" do
    it "keeps targets and executables as stored facts, not a verdict" do
      manifest = parsed(<<-YAML)
        name: sam
        targets:
          sam:
            main: src/sam.cr
          sam-helper:
            main: src/helper.cr
        executables:
          - sam
        YAML

      # Both are stored because a library that also ships a CLI has both, and a
      # single boolean gets that wrong in both directions without saying so.
      manifest.target_names.should eq(["sam", "sam-helper"])
      manifest.executable_names.should eq(["sam"])
      manifest.targets.should_not be_nil
      manifest.executables.should_not be_nil
    end

    it "reports a pure library as having neither" do
      manifest = parsed("name: radix\nversion: 0.4.1\n")

      manifest.targets.should be_nil
      manifest.executables.should be_nil
      manifest.target_names.should be_empty
      manifest.executable_names.should be_empty
    end

    it "ignores a targets key that is not a mapping" do
      # `targets: []` appears in the corpus. Storing it would make
      # `target_names` answer from a list of nothing, which is the same answer
      # as nil and one more shape every reader has to handle.
      manifest = parsed("name: x\ntargets: []\n")

      manifest.targets.should be_nil
      manifest.target_names.should be_empty
    end

    it "ignores an executables key that is not a list" do
      manifest = parsed("name: x\nexecutables: sam\n")

      manifest.executables.should be_nil
      manifest.executable_names.should be_empty
    end

    it "skips a non-string entry in executables rather than failing the parse" do
      manifest = parsed("name: x\nexecutables:\n  - sam\n  - 42\n")

      manifest.executable_names.should eq(["sam"])
    end
  end

  describe "a manifest that does not parse" do
    it "answers a sentence for an empty file rather than raising" do
      message = refused("")

      message.should eq("shard.yml is empty.")
    end

    it "treats whitespace as empty" do
      refused("   \n\n").should eq("shard.yml is empty.")
    end

    it "refuses a document that is valid YAML but not a mapping" do
      # `false` is a complete, valid YAML document. Accepting it would produce a
      # manifest with every field nil, which is indistinguishable on a page from
      # a manifest that parsed and simply said nothing.
      message = refused("false")

      message.should eq(
        "shard.yml is valid YAML but not a mapping, so it is not a shard specification."
      )
    end

    it "refuses a list, a bare string and a null document the same way" do
      [
        "- one\n- two\n",
        "just a sentence\n",
        "null\n",
      ].each do |source|
        refused(source).should contain("not a mapping")
      end
    end

    it "answers a sentence for broken YAML, with the line to open" do
      # Real shape: a tab where YAML wants spaces.
      message = refused("name: broken\ndependencies:\n\tkemal:\n")

      message.should start_with("shard.yml is not valid YAML at line ")
      message.should end_with(".")
      # The whole point of the sentence is that it is read by a person looking
      # at a shard page, so it must not carry a Crystal class name.
      message.should_not contain("YAML::ParseException")
      message.should_not contain("Exception")
    end

    it "does not repeat the line number inside the reason" do
      message = refused("name: broken\ndependencies:\n\tkemal:\n")

      # The message is built as "...at line N: <reason>", and YAML's own message
      # already ends with " at line N, column M". Left in, a reader gets the
      # location twice in one sentence.
      message.scan(" at line ").size.should eq(1)
    end

    it "never raises, whatever it is handed" do
      # The property, stated once over every shape the corpus has produced.
      [
        "",
        "false",
        "\t\n",
        "name: x\n\tbad: indent\n",
        "%YAML 1.3\n---\nname: x\n",
        "name: [unclosed\n",
        "a: *undefined_anchor\n",
      ].each do |source|
        result = ShardManifest.parse(source)
        result.should be_a(ShardManifest | String)
      end
    end
  end
end
