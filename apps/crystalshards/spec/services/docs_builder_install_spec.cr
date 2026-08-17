require "../spec_helper"

# The fetch phase's contract with the compile phase: hand over a COMPLETE
# tree, or hand over nothing.
#
# Two things make that true, and both are load bearing enough to pin.
#
# CRYSTAL_VERSION reaches `shards`, because shards otherwise shells out to
# `crystal` after writing the lock purely to read a version, and the launcher
# image has no compiler in it. The install then exits non-zero having already
# installed everything, which is the worst shape a failure can take.
#
# A failed install stops the build. It used to be logged and stepped over,
# which meant compiling whatever tree shards abandoned and publishing
# documentation quietly missing whatever could not be resolved. Nothing on the
# page would say so.

# Records what the sandbox was asked to do, so an example can assert the
# compile never started.
private class RecordingSandbox < CrystalShards::DocsSandbox
  getter? called = false

  def description : String
    "recording sandbox"
  end

  def crystal_version : String
    "9.9.9"
  end

  def build_docs(source_dir : String, output_dir : String) : Bool
    @called = true
    Dir.mkdir_p(output_dir)
    File.write(File.join(output_dir, DOCS_JSON), %({"program":{"name":"fixture"}}))
    true
  end
end

# A real repository, because DocsBuilder clones and checks out a tag before it
# installs anything, and a stub of that would be testing the stub.
private def repository_with_tag : String
  dir = File.tempname("install_spec_repo")
  Dir.mkdir_p(File.join(dir, "src"))
  File.write(File.join(dir, "shard.yml"), "name: fixture\nversion: 1.0.0\n")
  File.write(File.join(dir, "src", "fixture.cr"), "module Fixture\nend\n")
  # -c rather than relying on whatever the machine's global git config says.
  # A developer with signing turned on cannot commit or tag here without a
  # key, and that would fail this spec for a reason that has nothing to do
  # with what it is testing.
  run = ->(args : Array(String)) {
    output = IO::Memory.new
    flags = ["-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false", "-c", "tag.forceSignAnnotated=false"]
    status = Process.run("git", flags + args, chdir: dir, output: output, error: output)
    fail "git #{args.join(' ')} failed: #{output}" unless status.success?
  }

  run.call(["init", "--initial-branch", "main"])
  run.call(["config", "user.email", "spec@example.com"])
  run.call(["config", "user.name", "spec"])
  run.call(["add", "."])
  run.call(["commit", "-m", "fixture"])
  run.call(["tag", "-a", "-m", "fixture", "1.0.0"])

  dir
end

# Puts a `shards` of our own first on PATH. It records the environment it was
# given and exits with whatever the example asked for, which is the only way
# to see what the real one would have been handed.
private def with_shards_shim(exit_code : Int32, &)
  shim_dir = File.tempname("shards_shim")
  Dir.mkdir_p(shim_dir)
  record = File.join(shim_dir, "record.txt")

  File.write(File.join(shim_dir, "shards"), <<-SH)
  #!/bin/sh
  printf '%s' "${CRYSTAL_VERSION:-UNSET}" > "#{record}"
  echo "shim refused to resolve" >&2
  exit #{exit_code}
  SH
  File.chmod(File.join(shim_dir, "shards"), 0o755)

  previous = ENV["PATH"]
  ENV["PATH"] = "#{shim_dir}:#{previous}"

  begin
    yield record
  ensure
    ENV["PATH"] = previous
    FileUtils.rm_rf(shim_dir) if Dir.exists?(shim_dir)
  end
end

describe CrystalShards::DocsBuilder do
  describe "installing dependencies" do
    it "tells shards which compiler the sandbox will use" do
      sandbox = RecordingSandbox.new
      repo = repository_with_tag
      work_dir = File.tempname("install_spec_work")
      Dir.mkdir_p(work_dir)

      begin
        with_shards_shim(0) do |record|
          CrystalShards::DocsBuilder.new(sandbox).generate_docs(repo, "1.0.0", nil, work_dir)

          # The sandbox's own answer, not a constant read from somewhere else.
          # Dependencies resolved for one compiler and compiled by another is
          # a mismatch nothing downstream can detect.
          File.read(record).should eq("9.9.9")
        end
      ensure
        FileUtils.rm_rf(repo) if Dir.exists?(repo)
        FileUtils.rm_rf(work_dir) if Dir.exists?(work_dir)
      end
    end

    it "refuses to compile a tree shards could not finish" do
      sandbox = RecordingSandbox.new
      repo = repository_with_tag
      work_dir = File.tempname("install_spec_work")
      Dir.mkdir_p(work_dir)

      begin
        with_shards_shim(1) do
          expect_raises(Exception, /Could not install dependencies/) do
            CrystalShards::DocsBuilder.new(sandbox).generate_docs(repo, "1.0.0", nil, work_dir)
          end
        end

        # The point of failing: an incomplete lib/ that still compiles
        # publishes documentation missing whatever could not be resolved, and
        # the page says nothing about it.
        sandbox.called?.should be_false
      ensure
        FileUtils.rm_rf(repo) if Dir.exists?(repo)
        FileUtils.rm_rf(work_dir) if Dir.exists?(work_dir)
      end
    end
  end

  describe "reporting progress" do
    it "announces each step before performing it, in the order it performs them" do
      # The reader's whole view of a build that takes minutes. Announced
      # BEFORE the step runs, not after: a step reported on completion means
      # the page names whatever just finished while the slow thing it is
      # actually waiting on goes unnamed.
      sandbox = RecordingSandbox.new
      repo = repository_with_tag
      work_dir = File.tempname("step_spec_work")
      Dir.mkdir_p(work_dir)
      steps = [] of String

      begin
        with_shards_shim(0) do
          builder = CrystalShards::DocsBuilder.new(sandbox)
          builder.on_step = ->(step : String) { steps << step; nil }
          builder.generate_docs(repo, "1.0.0", nil, work_dir)
        end

        # Uploading is absent on purpose: it belongs to BuildDocsWorker, which
        # owns the artifact, not to the builder.
        steps.should eq(["cloning", "resolving", "dependencies", "documenting"])
      ensure
        FileUtils.rm_rf(repo) if Dir.exists?(repo)
        FileUtils.rm_rf(work_dir) if Dir.exists?(work_dir)
      end
    end

    it "builds without a reporter, for the paths that have no request row" do
      # The standard library build has no doc_build_requests row to update.
      # A builder nobody wired must not require wiring.
      sandbox = RecordingSandbox.new
      repo = repository_with_tag
      work_dir = File.tempname("step_spec_bare")
      Dir.mkdir_p(work_dir)

      begin
        with_shards_shim(0) do
          CrystalShards::DocsBuilder.new(sandbox).generate_docs(repo, "1.0.0", nil, work_dir)
        end
      ensure
        FileUtils.rm_rf(repo) if Dir.exists?(repo)
        FileUtils.rm_rf(work_dir) if Dir.exists?(work_dir)
      end
    end
  end
end
