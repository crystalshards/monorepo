# The hostile submission. Everything in this file is written as an attacker
# would write it: it tries to leave its execution context and reports, as
# parseable PROBE lines, exactly what each attempt found.
#
# Boundary shape, from DESIGN.md section 4 and the docs-build precedent
# (apps/docs-build/entrypoint.sh, apps/docs-build/sandbox/no-egress.c):
#
#   compile time   Macros expand while `crystal run` compiles the submission.
#                  A top-level `{% `...` %}` executes an arbitrary shell
#                  command in the compiling process. This is a DIFFERENT
#                  boundary from runtime: it runs in the compiler's process,
#                  before any user code executes, so it must be probed
#                  separately.
#   run time       The probes below run as ordinary Crystal in the submitted
#                  program.
#
# Every macro command is wrapped in `echo ... 1>&2` so it exits zero: a macro
# backtick RAISES when its command exits non-zero, which would kill the
# compile at the first blocked probe and make every later probe (and the real
# output) disappear. A fixture that dies at the first refusal looks exactly
# like a fixture that was fully contained.
#
# Probe line format, parsed by spec/confinement_spec.cr:
#
#   PROBE <name>: <result>
#
# Runtime probes print to stdout, macro probes to stderr, because backtick
# output surfaces on the compiler's stderr. The spec reads both channels from
# the runner's JSON response and FAILS LOUDLY when an expected PROBE line is
# absent: a missing line means the execution never produced it, which is a
# broken run, not a successful confinement.

# ------------------------------------------------------------ macro time ----
#
# Every probe names the tool it needs and reports NO-TOOL-<name> when that
# tool is absent, instead of letting a missing binary read as a refusal.
# This is not hypothetical: the first version of this fixture probed with
# curl, the runner image does not ship curl, and the probe reported REFUSED
# in a deliberately UNCONFINED run. The negative control caught it. A missing
# tool, a broken probe and a working sandbox look identical from the outside
# unless the probe says which one it is.
{% `echo "PROBE macro-env: $(if command -v printenv >/dev/null 2>&1; then if printenv TRYC_CANARY >/dev/null 2>&1; then echo LEAKED; else echo scrubbed; fi; else echo NO-TOOL-printenv; fi)" 1>&2` %}
# macro-net deliberately targets a literal IP over plain HTTP with a generous
# timeout. An earlier version fetched https://example.com with a 3 second
# limit and flaked: it reported REFUSED in an UNCONFINED run while the same
# command succeeded when run by hand, because a 3 second DNS-plus-TLS
# handshake is contended while the spec is building images and starting
# containers. A flaky negative control is worse than a missing one, because
# the tempting repair is to loosen the assertion until it stops complaining.
# DNS and TLS are not the boundary under test; reaching the network is. DNS
# is measured separately by runtime-dns. The seccomp filter refuses socket
# creation regardless of destination, so a literal IP is still refused when
# confined, and the failing exit code is carried into the result so a future
# ambiguity is diagnosable instead of a guess.
{% `echo "PROBE macro-net: $(if command -v wget >/dev/null 2>&1; then if wget -q -T 10 -O /dev/null http://1.1.1.1; then echo REACHABLE; else echo "REFUSED (wget rc=$?)"; fi; else echo NO-TOOL-wget; fi)" 1>&2` %}
{% `echo "PROBE macro-proc1: $(if command -v head >/dev/null 2>&1; then if head -c 1 /proc/1/environ >/dev/null 2>&1; then echo READABLE; else echo REFUSED; fi; else echo NO-TOOL-head; fi)" 1>&2` %}

require "socket"

# ------------------------------------------------------- legitimate body ----
# Real lesson-shaped code, so a passing containment run is distinguishable
# from an execution that simply broke. The spec asserts LESSON_OK appears and
# that the runner returned the final expression's value.
module TrycrystalLesson
  FIB = [1, 1, 2, 3, 5, 8]

  def self.answer : Int32
    FIB.sum
  end

  def self.greeting(name : String) : String
    "hello from crystal, #{name}"
  end
end

puts "LESSON_OK sum=#{TrycrystalLesson.answer} #{TrycrystalLesson.greeting("visitor")}"

# ------------------------------------------------------------- run time ----
# The canary the operator set on the server container. The confined child's
# environment is an allowlist, so this must be nil no matter what the server
# process holds.
canary = ENV["TRYC_CANARY"]?
puts "PROBE runtime-env: #{canary ? "LEAKED" : "scrubbed"}"

# An outbound connection. Confined, socket(AF_INET) returns EAFNOSUPPORT from
# the seccomp filter; the errno is printed because "address family not
# supported" is the filter's own refusal, while anything else (refused,
# unreachable, timeout) would mean the socket was created and the filter is
# not the reason for the failure.
begin
  socket = TCPSocket.new("example.com", 443, connect_timeout: 3)
  socket.close
  puts "PROBE runtime-net: REACHABLE"
rescue ex
  puts "PROBE runtime-net: REFUSED (#{ex.class}: #{ex.message.to_s.split('\n').first? || ex.message})"
end

# The link-local metadata server. On Cloud Run it mints tokens for the
# service's own identity, and no VPC or egress setting covers it, so it is
# probed explicitly rather than assumed to follow the public internet.
begin
  socket = TCPSocket.new("169.254.169.254", 80, connect_timeout: 2)
  socket.close
  puts "PROBE runtime-metadata: REACHABLE"
rescue ex
  puts "PROBE runtime-metadata: REFUSED (#{ex.class}: #{ex.message.to_s.split('\n').first? || ex.message})"
end

# Name resolution is egress too: the name looked up is data, and the lookup
# reaches a resolver.
begin
  Socket::Addrinfo.resolve("example.com", "http", type: Socket::Type::STREAM)
  puts "PROBE runtime-dns: RESOLVED"
rescue ex
  puts "PROBE runtime-dns: REFUSED (#{ex.class})"
end

# The supervisor's environment. The runner process holds whatever the platform
# handed the container, including TRYC_CANARY; user code runs as a lower uid
# so /proc/1/environ must be unreadable. Distinct states on purpose:
#   READABLE+CANARY-FOUND   full leak, the negative control must show this
#   READABLE                readable but no canary (misconfigured scrub)
#   OPEN-UNREADABLE         opened but read failed, treated as a leak surface
#   REFUSED                 the uid split held
begin
  environ = File.read("/proc/1/environ")
  found = environ.includes?("TRYC_CANARY") ? "+CANARY-FOUND" : ""
  puts "PROBE runtime-proc1env: READABLE#{found}"
rescue ex
  if ex.message.to_s.includes?("Permission denied") || ex.message.to_s.includes?("Operation not permitted")
    puts "PROBE runtime-proc1env: REFUSED"
  else
    puts "PROBE runtime-proc1env: OPEN-UNREADABLE (#{ex.class})"
  end
end

# The supervisor's memory. Same uid reasoning; opened-vs-read distinguished
# because a plain "failed" collapses open-refusal and read-refusal, and they
# mean different things.
begin
  File.open("/proc/1/mem") do |file|
    file.read_byte
    puts "PROBE runtime-proc1mem: READABLE"
  end
rescue ex
  message = ex.message.to_s
  if message.includes?("Permission denied") || message.includes?("Operation not permitted")
    puts "PROBE runtime-proc1mem: REFUSED"
  elsif message.includes?("Input/output") || message.includes?("No such")
    puts "PROBE runtime-proc1mem: OPEN-UNREADABLE"
  else
    puts "PROBE runtime-proc1mem: OPEN-UNREADABLE (#{ex.class})"
  end
end

# Who we are. Confined code must not be root; uid 0 here is a confinement
# failure, not a detail. (LibC in older Crystal binds getuid but not getgid,
# so uid is the reported fact.)
puts "PROBE runtime-uid: uid=#{LibC.getuid}"

# Writing outside the scratch directory. The container filesystem is not
# read-only on this platform; what stops this write is the non-root uid, so
# both roots (/ and /etc) are probed and each result reported separately.
begin
  File.write("/escaped-from-submission", "x")
  puts "PROBE runtime-rootfs: WRITABLE-root"
rescue ex
  puts "PROBE runtime-rootfs: root-refused"
end
begin
  File.write("/etc/escaped-from-submission", "x")
  puts "PROBE runtime-rootfs-etc: WRITABLE-etc"
rescue ex
  puts "PROBE runtime-rootfs-etc: etc-refused"
end

# The kernel's own account of our confinement: effective capabilities (all
# zero means nothing is held), no_new_privs (1 means setuid cannot regain
# privilege), and seccomp mode (2 means a filter is installed in THIS process,
# not merely an ancestor's).
begin
  status = File.read("/proc/self/status")
  caps = status.lines.select { |line| line.starts_with?("CapEff:") }.first?.try(&.strip) || "CapEff: absent"
  nnp = status.lines.select { |line| line.starts_with?("NoNewPrivs:") }.first?.try(&.strip) || "NoNewPrivs: absent"
  seccomp = status.lines.select { |line| line.starts_with?("Seccomp:") }.first?.try(&.strip) || "Seccomp: absent"
  puts "PROBE runtime-caps: #{caps} | #{nnp} | #{seccomp}"
rescue ex
  puts "PROBE runtime-caps: unreadable (#{ex.class})"
end

# The final expression. The runner inspects it and returns it as `value`, so
# the spec can assert the WHOLE path (compile, run, capture) worked, not just
# that nothing leaked.
"confinement-proof-complete"
