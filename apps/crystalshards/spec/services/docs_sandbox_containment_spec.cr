require "../spec_helper"

DOCS_BUILD_SPEC_IMAGE = "crystalshards/docs-build:spec"
DOCS_BUILD_CONTEXT    = File.expand_path("../../../docs-build", __DIR__)

# Proves the confinement, rather than asserting that we configured flags.
#
# The fixture below is a working shard whose macros try, at compile time, to
# read a credential out of the environment, reach the public internet, reach
# the link-local metadata server, resolve a name, read a file on the host that
# was never handed to the build, and write outside the one directory the build
# is meant to produce. That is not contrived: a top-level `{% \`...\` %}` runs
# while `crystal docs` compiles, so anything published to the registry can do
# this.
#
# Every probe command ends in a fallback that exits zero. A macro backtick
# raises when its command exits non-zero, so without that the compile would
# die at the first probe and the rest would never run, which would look like
# confinement while proving almost none of it.
#
# Skipped when docker is unavailable, because the point is to exercise the real
# boundary and a mocked one would prove nothing.
private def docker_available? : Bool
  Process.run("docker", ["info"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
rescue
  false
end

# `host_secret_path` is a real file on this machine that is deliberately NOT
# mounted into the sandbox, so reading it would be a genuine escape. `/out` is
# the build's own output mount and is expected to be writable, which is why the
# filesystem probe targets `/etc` instead.
private def hostile_source(host_secret_path : String) : String
  <<-CRYSTAL
  {% `printenv CANARY_CREDENTIAL > /out/env.txt 2>&1 || echo unreadable > /out/env.txt` %}
  {% `curl -s -m 3 -o /out/net.txt https://example.com || echo blocked > /out/net.txt` %}
  {% `curl -s -m 3 -H 'Metadata-Flavor: Google' -o /out/metadata.txt http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token || echo blocked > /out/metadata.txt` %}
  {% `getent hosts example.com > /out/dns.txt 2>&1 || echo blocked > /out/dns.txt` %}
  {% `id > /out/whoami.txt 2>&1` %}
  {% `cat #{host_secret_path} > /out/host_read.txt 2>&1 || echo unreachable > /out/host_read.txt` %}
  {% `touch /etc/escaped 2>/dev/null && echo WRITABLE > /out/rootfs.txt || echo readonly > /out/rootfs.txt` %}

  module Hostile
    # Something real to document, so a successful build is distinguishable
    # from a build that never ran.
    def self.greet : String
      "hello"
    end
  end
  CRYSTAL
end

# The same three network probes, run in the same image, with the network left
# in place.
#
# Without this the assertions below pass whether or not the sandbox blocks
# anything: a broken probe, a missing curl and a host with no route all look
# exactly like successful confinement. This is the control that gives the word
# "blocked" a meaning.
private def egress_control_source : String
  <<-CRYSTAL
  {% `curl -s -m 5 -o /out/net.txt https://example.com || echo blocked > /out/net.txt` %}
  {% `getent hosts example.com > /out/dns.txt 2>&1 || echo blocked > /out/dns.txt` %}

  module Control
    def self.greet : String
      "hello"
    end
  end
  CRYSTAL
end

private def write_shard(dir : String, name : String, source : String)
  Dir.mkdir_p(File.join(dir, "src"))
  File.write(File.join(dir, "shard.yml"), "name: #{name}\nversion: 0.1.0\n")
  File.write(File.join(dir, "src", "#{name}.cr"), source)
end

# Built once, because it is the same image for every example here and a
# rebuild of an unchanged context is still a few seconds of docker.
private class DocsBuildImage
  @@built : Bool? = nil

  def self.available? : Bool
    @@built ||= Process.run(
      "docker",
      ["build", "-q", "-t", DOCS_BUILD_SPEC_IMAGE, DOCS_BUILD_CONTEXT],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close
    ).success?
  end
end

private def docs_build_image_available? : Bool
  DocsBuildImage.available?
end

# A shard as the launcher would hand it over: already cloned, already
# `shards install`ed, packed into the tarball the Job downloads.
private def shard_tarball(name : String, source : String, extra = {} of String => String) : Bytes
  dir = File.tempname("spec_shard")
  Dir.mkdir_p(File.join(dir, "src"))
  File.write(File.join(dir, "shard.yml"), "name: #{name}\nversion: 0.1.0\n")
  File.write(File.join(dir, "src", "#{name}.cr"), source)
  extra.each do |path, contents|
    File.write(File.join(dir, path), contents)
  end

  tarball = File.tempname("spec_shard", ".tar.gz")
  Process.run("tar", ["-czf", tarball, "-C", dir, "."]).success?.should be_true
  File.read(tarball).to_slice
ensure
  FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  File.delete(tarball) if tarball && File.exists?(tarball)
end

# Stands in for the storage the launcher signs urls against: serves the source
# on GET and accepts the artifact and the diagnostic on PUT.
#
# It is a real socket over real TLS, not a file:// url and not plain HTTP. The
# positive control depends on it: the compile phase is asked to make the
# identical outbound HTTPS request, to the same host and port, that the fetch
# phase completed seconds earlier in the same container. A control that used a
# different scheme, or no connection at all, would not tell us the refusal
# came from the confinement.
#
# The certificate is generated per run and its own CA bundle is mounted over
# the container's, so the fetch phase trusts this origin. That matters for
# what the compile phase's failure means: with the filter in place curl never
# gets as far as a certificate, so if trust were the reason a probe failed,
# the probe would prove nothing about egress.
private class SpecOrigin
  getter uploaded = {} of String => String
  @port : Int32

  def initialize
    @sources = {} of String => Bytes
    @certificate = File.tempname("spec_origin", ".crt")
    @key = File.tempname("spec_origin", ".key")

    Process.run("openssl", [
      "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
      "-subj", "/CN=host.docker.internal",
      "-addext", "subjectAltName=DNS:host.docker.internal",
      "-keyout", @key, "-out", @certificate,
    ], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true

    tls = OpenSSL::SSL::Context::Server.new
    tls.certificate_chain = @certificate
    tls.private_key = @key

    @server = HTTP::Server.new do |context|
      handle(context)
    end
    @port = @server.bind_tls("0.0.0.0", 0, tls).port
    spawn { @server.listen }
  end

  def serve(name : String, body : Bytes)
    @sources[name] = body
  end

  # The exact GET the fetch phase performs. A probe macro is handed this
  # literal string so the compile phase can attempt the identical request.
  def source_url(name : String) : String
    "#{base}/#{name}.tar.gz"
  end

  def upload_url(name : String) : String
    "#{base}/#{name}-docs.json"
  end

  # host-gateway is how a container reaches a listener on the host.
  def build(name : String) : NamedTuple(status: Int32, output: String)
    output = IO::Memory.new
    status = Process.run(
      "docker",
      [
        "run", "--rm",
        "--add-host", "host.docker.internal:host-gateway",
        "-v", "#{@certificate}:/etc/ssl/certs/ca-certificates.crt:ro",
        "-e", "DOCS_SOURCE_URL=#{source_url(name)}",
        "-e", "DOCS_UPLOAD_URL=#{upload_url(name)}",
        "-e", "DOCS_UPLOAD_CONTENT_TYPE=application/json",
        "-e", "DOCS_LOG_UPLOAD_URL=#{base}/#{name}-build.log",
        # Sent explicitly, as the launcher sends it. Leaving the entrypoint's
        # default to supply it would hide the day the signed header and the
        # sent header stop matching.
        "-e", "DOCS_LOG_CONTENT_TYPE=text/plain",
        DOCS_BUILD_SPEC_IMAGE,
      ],
      output: output,
      error: output
    )

    {status: status.exit_code, output: output.to_s}
  end

  def close
    @server.close
    File.delete(@certificate) if File.exists?(@certificate)
    File.delete(@key) if File.exists?(@key)
  end

  private def base : String
    "https://host.docker.internal:#{@port}"
  end

  private def handle(context : HTTP::Server::Context)
    key = context.request.path.lstrip('/')

    case context.request.method
    when "GET"
      if body = @sources[key]?
        context.response.content_type = "application/gzip"
        context.response.write(body)
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when "PUT"
      @uploaded[key] = context.request.body.try(&.gets_to_end) || ""
      context.response.status = HTTP::Status::OK
    else
      context.response.status = HTTP::Status::METHOD_NOT_ALLOWED
    end
  end
end

# The docker sandbox with `--network none` swapped for a working network, so
# the probes can be shown succeeding. Everything else about the run is
# identical, which is what makes the comparison worth anything.
private class NetworkedDocsSandbox < CrystalShards::DockerDocsSandbox
  protected def network_mode : String
    "bridge"
  end
end

describe "documentation sandbox containment" do
  it "denies a hostile shard the environment, the network and the host" do
    pending! "docker is not available" unless docker_available?

    source = File.tempname("hostile_src")
    output = File.tempname("hostile_out")
    host_only = File.tempname("host_only")

    Dir.mkdir_p(output)
    Dir.mkdir_p(host_only)

    # A file on the host that the sandbox is never given. Reading it from
    # inside the build would mean the boundary leaks.
    host_secret_path = File.join(host_only, "host_secret.txt")
    File.write(host_secret_path, "host-file-must-not-be-readable")

    write_shard(source, "hostile", hostile_source(host_secret_path))

    # A credential in this process's environment, exactly as the launcher
    # holds STORAGE_SECRET_KEY. The build must not be able to see it.
    ENV["CANARY_CREDENTIAL"] = "canary-must-not-escape"

    begin
      built = CrystalShards::DockerDocsSandbox.new.build_docs(source, output)

      # A missing probe file must fail rather than read as empty. Otherwise a
      # build that never ran satisfies every "should_not contain" assertion
      # below and the spec passes while proving nothing.
      read = ->(name : String) {
        path = File.join(output, name)
        fail "the build produced no #{name}, so it did not run" unless File.exists?(path)
        File.read(path).strip
      }

      # The credential is the whole game: this is what an attacker publishes a
      # shard to steal.
      read.call("env.txt").should_not contain("canary-must-not-escape")

      # No egress, so nothing can be shipped out even if it were readable.
      read.call("net.txt").should eq("blocked")

      # The metadata server is not on the public internet and no egress
      # setting covers it. It mints tokens for the build's own service
      # account, so a control that stops example.com and leaves this reachable
      # has closed the cheap half of the hole.
      read.call("metadata.txt").should eq("blocked")

      # Name resolution is egress too. A macro that cannot connect but can
      # still resolve has a channel: the name it looks up is data, and the
      # lookup reaches a resolver.
      read.call("dns.txt").should eq("blocked")

      # A host file outside the mounts stays outside.
      read.call("host_read.txt").should_not contain("host-file-must-not-be-readable")

      # The container filesystem is read-only apart from the declared mounts.
      read.call("rootfs.txt").should eq("readonly")

      # Not root inside the container.
      read.call("whoami.txt").should contain("uid=1000")

      # The build ran and produced real documentation, so the confinement is
      # not passing merely by breaking the build. The one artifact is the
      # JSON document; it has to exist, parse, and contain the module the
      # fixture defines.
      built.should be_true
      docs_json_path = File.join(output, "docs.json")
      fail "the build produced no docs.json, so it did not run" unless File.exists?(docs_json_path)
      document = JSON.parse(File.read(docs_json_path))
      document["program"]?.should_not be_nil
      File.read(docs_json_path).should contain("Hostile")
    ensure
      ENV.delete("CANARY_CREDENTIAL")
      FileUtils.rm_rf(source) if Dir.exists?(source)
      FileUtils.rm_rf(output) if Dir.exists?(output)
      FileUtils.rm_rf(host_only) if Dir.exists?(host_only)
    end
  end

  it "reaches the network from the same probes when the network is left in place" do
    pending! "docker is not available" unless docker_available?

    source = File.tempname("control_src")
    output = File.tempname("control_out")
    Dir.mkdir_p(output)

    write_shard(source, "control", egress_control_source)

    begin
      NetworkedDocsSandbox.new.build_docs(source, output)

      read = ->(name : String) {
        path = File.join(output, name)
        fail "the control build produced no #{name}, so it did not run" unless File.exists?(path)
        File.read(path).strip
      }

      # If these come back "blocked" the machine running the suite has no
      # egress, and the assertions in the spec above are vacuous rather than
      # reassuring. Failing here is the correct outcome: it says the proof is
      # unavailable, not that the sandbox is sound.
      read.call("net.txt").should_not eq("blocked")
      read.call("dns.txt").should_not eq("blocked")
    ensure
      FileUtils.rm_rf(source) if Dir.exists?(source)
      FileUtils.rm_rf(output) if Dir.exists?(output)
    end
  end

  # The docker sandbox proves the compile is confined when the CONTAINER has no
  # network. Production cannot use that: the docs-build Job has to reach two
  # signed urls, so its container keeps its network and the confinement has to
  # come from inside. These exercise that image, which is the one that actually
  # runs untrusted code.
  describe "the docs-build image" do
    it "blocks every route off the machine in the compile phase and none in the fetch phase" do
      pending! "docker is not available" unless docker_available?

      built = Process.run(
        "docker",
        ["build", "-q", "-t", DOCS_BUILD_SPEC_IMAGE, DOCS_BUILD_CONTEXT],
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      pending! "could not build #{DOCS_BUILD_SPEC_IMAGE}" unless built.success?

      output = IO::Memory.new
      # The probe reports every route it can find: AF_INET, AF_INET6,
      # AF_PACKET, AF_VSOCK, an io_uring IORING_OP_SOCKET submission, and a
      # socket requested through the x32 syscall number. --expect-closed exits
      # non-zero if any of them is open.
      status = Process.run(
        "docker",
        [
          "run", "--rm", "--entrypoint", "/usr/local/bin/no-egress",
          DOCS_BUILD_SPEC_IMAGE, "/usr/local/bin/egress-probe", "--expect-closed",
        ],
        output: output,
        error: output
      )

      status.success?.should be_true
      text = output.to_s

      # EAFNOSUPPORT, and specifically not some other failure: the guard
      # refuses to run at all unless every one of these carries the errno its
      # own filter returns, which is what separates "we denied it" from "this
      # host would have refused anyway".
      text.should contain("AF_INET socket         blocked Address family not supported by protocol")
      text.should contain("AF_INET6 socket        blocked Address family not supported by protocol")
      text.should contain("AF_VSOCK socket        blocked Address family not supported by protocol")

      # io_uring can create and connect a socket from inside the ring without
      # issuing socket(2), so a filter that only watches socket(2) is bypassed
      # outright. This is the assertion that the ring cannot be created.
      text.should contain("io_uring               blocked")

      # x32 numbers its syscalls with a high bit set while still reporting
      # AUDIT_ARCH_X86_64, so an equality test on the number can be walked
      # past. The filter kills instead of returning an error, hence a signal.
      text.should contain("x32 socket number      blocked")

      # The positive control, in the same image, without the guard. If the
      # probe cannot find a route here then the run above proves nothing.
      control = IO::Memory.new
      Process.run(
        "docker",
        [
          "run", "--rm", "--entrypoint", "/usr/local/bin/egress-probe",
          DOCS_BUILD_SPEC_IMAGE, "--expect-open",
        ],
        output: control,
        error: control
      ).success?.should be_true

      control.to_s.should contain("AF_INET socket         OPEN")
    end

    # The probe above shows the guard works. This shows the BUILD works: the
    # real entrypoint, fetching over a real socket from a real origin, then
    # compiling with that route gone, then publishing. Anything less leaves
    # the possibility that the confinement is correct and the build around it
    # is not, which is the same as having neither.
    it "documents a normal shard and refuses one that reaches for the network" do
      pending! "docker is not available" unless docker_available?
      pending! "could not build #{DOCS_BUILD_SPEC_IMAGE}" unless docs_build_image_available?

      origin = SpecOrigin.new
      origin.serve("benign.tar.gz", shard_tarball("benign", <<-CRYSTAL))
        module Benign
          # A shard that does nothing unusual.
          def self.add(a : Int32, b : Int32) : Int32
            a + b
          end
        end
        CRYSTAL

      # `run` compiles and executes a helper program while the shard is being
      # compiled, and the helper opens an HTTP connection. This is the pattern
      # the change is aimed at, and the one a maintainer has to be told about.
      fetcher = %(require "http/client"\nputs HTTP::Client.get("https://example.com").body.size\n)
      greedy_source = <<-CRYSTAL
        module Greedy
          {{ run("./fetcher") }}
        end
        CRYSTAL

      origin.serve(
        "greedy.tar.gz",
        shard_tarball("greedy", greedy_source, {"src/fetcher.cr" => fetcher})
      )

      # The probe shard. Every command ends in a fallback that exits zero, so
      # the compile survives and the result of each attempt is readable. The
      # first probe is the whole positive control: it is the SAME outbound
      # HTTPS GET, to the same host, port and path, that this container
      # completed successfully in its fetch phase moments earlier.
      origin.serve("prober.tar.gz", shard_tarball("prober", <<-CRYSTAL))
        {% `echo "PROBE samereq  : $(curl -s -m 5 -o /dev/null -w %{http_code} #{origin.source_url("prober")} 2>&1 || echo REFUSED)" 1>&2` %}
        {% `echo "PROBE https    : $(curl -s -m 5 -o /dev/null -w %{http_code} https://example.com 2>&1 || echo REFUSED)" 1>&2` %}
        {% `echo "PROBE metadata : $(curl -s -m 5 -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token 2>&1 || echo REFUSED)" 1>&2` %}
        {% `echo "PROBE dns      : $(getent hosts example.com 2>&1 || echo REFUSED)" 1>&2` %}
        {% `echo "PROBE ownenv   : $(printenv DOCS_UPLOAD_URL 2>&1 || echo REFUSED)" 1>&2` %}
        {% `echo "PROBE procenv  : $(grep -ac DOCS_UPLOAD_URL /proc/1/environ 2>&1 || echo REFUSED)" 1>&2` %}
        {% `echo "PROBE whoami   : $(id)" 1>&2` %}

        module Prober
          # Something real to document, so a build that never ran is not
          # mistaken for a build that was contained.
          def self.greet : String
            "hello"
          end
        end
        CRYSTAL

      begin
        benign = origin.build("benign")

        # Exit zero, and a real document arrived at the key the launcher
        # signed, so the fetch reached the origin over a socket and the
        # compile still worked without one.
        benign[:status].should eq(0)
        origin.uploaded["benign-docs.json"]?.should_not be_nil
        JSON.parse(origin.uploaded["benign-docs.json"])["program"]?.should_not be_nil
        origin.uploaded["benign-docs.json"].should contain("Benign")

        # The fetch phase reported the network reachable, in the same run that
        # the compile phase reported it gone. One without the other is not a
        # measurement.
        benign[:output].should contain("AF_INET socket         OPEN")
        benign[:output].should contain("AF_INET socket         blocked")

        # The probe shard: every route refused, and a document produced
        # anyway.
        prober = origin.build("prober")
        prober[:status].should eq(0)
        origin.uploaded["prober-docs.json"].should contain("Prober")

        # The same HTTPS GET this container completed in its fetch phase. It
        # is the one assertion here that cannot be satisfied by a broken
        # probe, a missing curl, or a machine with no network, because the
        # identical request demonstrably worked minutes earlier in the same
        # process tree.
        prober[:output].should contain("PROBE samereq  : REFUSED")

        # An outbound HTTPS request to the public internet.
        prober[:output].should contain("PROBE https    : REFUSED")

        # The link-local metadata server, which mints tokens for this Job's
        # own service account and is not reached over any VPC, so no egress
        # setting would have covered it.
        prober[:output].should contain("PROBE metadata : REFUSED")

        # Name resolution is egress too: the name looked up is data, and the
        # lookup reaches a resolver.
        prober[:output].should contain("PROBE dns      : REFUSED")
        # env -i, so the capabilities are not in the compile's environment.
        prober[:output].should contain("PROBE ownenv   : REFUSED")

        # THE ONE THING THAT IS NOT CLOSED, pinned here so nobody reads the
        # silence above as safety.
        #
        # The compile runs as the same uid as the entrypoint, so it can read
        # that process's environment out of /proc and find the three signed
        # urls. Nothing available to an unprivileged, single uid container
        # closes this: PR_SET_DUMPABLE is reset by execve, a pid namespace
        # needs CLONE_NEWUSER which runtimes deny without CAP_SYS_ADMIN, and
        # hidepid needs a mount namespace. entrypoint.sh explains why the
        # reachable damage is bounded to this build's own scratch objects
        # inside a signature that expires in minutes.
        #
        # This asserts the leak rather than pretending it is shut. If someone
        # closes it, with a broker or a second container, this line fails and
        # they get to delete it on purpose.
        prober[:output].should contain("PROBE procenv  : 1")
        prober[:output].should contain("PROBE ownenv   : REFUSED")

        # Unprivileged, so it cannot overwrite curl or the compiler that the
        # phase after it runs.
        prober[:output].should contain("uid=1000")

        greedy = origin.build("greedy")

        # 2 is "reached for the network while compiling", which the entrypoint
        # only claims when the compiler's output carries the errno a denied
        # socket returns. A shard that merely failed to compile exits 1.
        greedy[:status].should eq(2)
        origin.uploaded["greedy-docs.json"]?.should be_nil

        # The reason has to reach the reader, and it has to lead: crystaldocs
        # keeps the front of this text, so an explanation after the compiler's
        # backtrace would be truncated away before anybody saw it.
        diagnostic = origin.uploaded["greedy-build.log"]
        diagnostic.should_not be_nil
        diagnostic.lines.first.should contain("tried to use the network while it was being compiled")
        diagnostic.should contain("Refusing this is deliberate")
        diagnostic.should contain("crystal docs said:")
        diagnostic.should contain("Address family not supported by protocol")

        # And it must not carry the capabilities it was handed.
        diagnostic.should_not contain("docs-origin")
        diagnostic.should_not contain(origin.upload_url("greedy"))
      ensure
        origin.close
      end
    end
  end
end
