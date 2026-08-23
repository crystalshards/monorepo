/* Vendored from apps/docs-build/sandbox/no-egress.c. Do not edit in place:
 * change the docs-build original and recopy. The runner execs this helper
 * in confined mode because it is the filter this project already proves
 * against untrusted code, and a Crystal port of the same BPF hung
 * `crystal run` (exit 137, empty streams) on aarch64.
 */

/*
 * no-egress: run a command with no way off this machine.
 *
 *   no-egress <command> [args...]
 *
 * This is the boundary between the fetch phase and the compile phase of a
 * documentation build. `shards install` and the two signed URLs need the
 * network. `crystal docs` expands the shard's macros, which is third party
 * code execution, so it must not have it.
 *
 * The mechanism is a seccomp filter the process installs on ITSELF and then
 * carries across execve. That choice is not arbitrary. The alternatives were
 * measured, not assumed:
 *
 *   A network namespace with no route is stronger in principle, but creating
 *   one needs CLONE_NEWUSER|CLONE_NEWNET, and every mainstream container
 *   runtime denies those to a process without CAP_SYS_ADMIN. Buying the
 *   namespace means granting CAP_SYS_ADMIN or dropping the runtime's own
 *   seccomp profile, which costs more than the namespace is worth.
 *
 *   An iptables rule needs CAP_NET_ADMIN, and a capability that can add a
 *   rule can remove one.
 *
 *   Cloud Run VPC egress settings cannot express "not for this phase", and
 *   they do not cover 169.254.169.254 at all: the metadata server is answered
 *   inside the sandbox and never traverses a VPC. Blocking public egress and
 *   leaving link-local reachable is the shape of the hole, not the fix.
 *
 * A seccomp filter needs no privilege, applies to this process and every
 * descendant, survives execve, and CANNOT BE REMOVED. There is no
 * SECCOMP_UNSET_MODE_FILTER. Filters only ever stack, and each one can only
 * narrow what is allowed. So the compile inherits a rule that the compile has
 * no way to lift.
 *
 * What an attacker has to defeat, in order:
 *
 *   1. Get an fd for something routable. socket(2) is restricted to AF_UNIX
 *      and AF_NETLINK, neither of which leaves the host.
 *   2. Use io_uring instead. IORING_OP_SOCKET and IORING_OP_CONNECT do their
 *      work inside the ring and never issue the syscalls a filter can see;
 *      this is a real, tested bypass of a socket-only filter, so the three
 *      io_uring syscalls are denied outright and the ring can never exist.
 *   3. Borrow an fd we already opened. We refuse to start if any inherited
 *      descriptor is a routable socket, and close every other inherited
 *      descriptor above stderr.
 *   4. Reach into the root parent, which still holds the signed URLs. ptrace
 *      and process_vm_readv/writev are denied here, and the compile runs as
 *      uid 1000 while the parent stays root, so /proc/<parent>/environ and
 *      /proc/<parent>/mem are unreadable. The image containment spec proves
 *      those refusals in the real process tree.
 *   5. Regain privilege through a setuid binary. no_new_privs forbids it.
 *   6. Find a kernel bug in seccomp or io_uring. That is the residual, and it
 *      is the same residual every container has.
 *
 * The filter is verified in this process, after installation and before the
 * exec, on every single run. A build whose confinement could not be proven
 * does not become a build that runs unconfined; it exits non-zero with a
 * message the launcher turns into a visible failure.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

#if defined(__aarch64__)
#define GUARD_AUDIT_ARCH AUDIT_ARCH_AARCH64
#elif defined(__x86_64__)
#define GUARD_AUDIT_ARCH AUDIT_ARCH_X86_64
#else
#error "no-egress has not been reviewed for this architecture"
#endif

#ifndef SECCOMP_RET_KILL_PROCESS
#define SECCOMP_RET_KILL_PROCESS 0x80000000U
#endif

#ifndef AF_VSOCK
#define AF_VSOCK 40
#endif

/* On x86_64 the x32 ABI reports AUDIT_ARCH_X86_64 but numbers its syscalls
 * with this bit set, so socket() arrives as __NR_socket | 0x40000000 and none
 * of the equality tests below would match it. Rejecting the whole range is
 * the only safe reading. aarch64 has no x32 and no syscall anywhere near this
 * number, so the same instruction is correct there and costs one comparison. */
#ifndef __X32_SYSCALL_BIT
#define __X32_SYSCALL_BIT 0x40000000U
#endif

/* Exit codes the entrypoint maps onto a human readable build failure. Kept
 * out of the 1..2 range so they cannot be confused with a compiler failure. */
#define EXIT_NO_NEW_PRIVS 70
#define EXIT_FILTER 71
#define EXIT_NOT_PROVEN 72
#define EXIT_INHERITED_SOCKET 73
#define EXIT_EXEC 74
#define EXIT_PRIVILEGE 75

/* Indices into the filter, so the relative jumps below are derived rather
 * than counted by hand. A miscounted BPF offset is a filter that quietly
 * allows the wrong thing, which is exactly the failure this file exists to
 * prevent, so the assertion at the end of the array pins the layout. */
enum {
  L_LOAD_ARCH,
  L_TEST_ARCH,
  L_KILL_ARCH,
  L_LOAD_NR,
  L_TEST_X32,
  L_IS_SOCKET,
  L_IS_SOCKETPAIR,
  L_IS_URING_SETUP,
  L_IS_URING_ENTER,
  L_IS_URING_REGISTER,
  L_IS_PTRACE,
  L_IS_VM_READV,
  L_IS_VM_WRITEV,
  L_ALLOW_OTHER,
  L_LOAD_DOMAIN,
  L_IS_UNIX,
  L_IS_NETLINK,
  L_DENY_FAMILY,
  L_DENY_PERM,
  L_ALLOW_SOCKET,
  L_KILL_X32,
  L_COUNT
};

#define JT(from, to) ((to) - (from) - 1)

static struct sock_filter filter[] = {
    [L_LOAD_ARCH] =
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
    [L_TEST_ARCH] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, GUARD_AUDIT_ARCH,
                             JT(L_TEST_ARCH, L_LOAD_NR), 0),
    /* A syscall arriving under a different personality is not something this
     * filter has been reasoned about for, so it ends the process rather than
     * being allowed through unexamined. */
    [L_KILL_ARCH] = BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),

    [L_LOAD_NR] =
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
    /* Forward jump, because BPF offsets are unsigned: the kill this reaches
     * for is the one at the tail, not L_KILL_ARCH above. */
    [L_TEST_X32] = BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, __X32_SYSCALL_BIT,
                            JT(L_TEST_X32, L_KILL_X32), 0),

    /* socket(2) and socketpair(2) both take the address family in arg 0. */
    [L_IS_SOCKET] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socket,
                             JT(L_IS_SOCKET, L_LOAD_DOMAIN), 0),
    [L_IS_SOCKETPAIR] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socketpair,
                                 JT(L_IS_SOCKETPAIR, L_LOAD_DOMAIN), 0),

    /* io_uring submits socket, connect and send as ring opcodes. None of them
     * reach a filter, so the ring itself is what has to be unavailable. */
    [L_IS_URING_SETUP] =
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_io_uring_setup,
                 JT(L_IS_URING_SETUP, L_DENY_PERM), 0),
    [L_IS_URING_ENTER] =
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_io_uring_enter,
                 JT(L_IS_URING_ENTER, L_DENY_PERM), 0),
    [L_IS_URING_REGISTER] =
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_io_uring_register,
                 JT(L_IS_URING_REGISTER, L_DENY_PERM), 0),

    /* The parent is still holding the signed upload URL while this runs. */
    [L_IS_PTRACE] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_ptrace,
                             JT(L_IS_PTRACE, L_DENY_PERM), 0),
    [L_IS_VM_READV] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_process_vm_readv,
                               JT(L_IS_VM_READV, L_DENY_PERM), 0),
    [L_IS_VM_WRITEV] =
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_process_vm_writev,
                 JT(L_IS_VM_WRITEV, L_DENY_PERM), 0),

    /* Everything else is a normal compile doing normal things. This is a
     * filter against leaving the machine, not a general syscall allowlist:
     * narrowing it further would break `macro run`, which legitimately
     * compiles and executes a helper program. */
    [L_ALLOW_OTHER] = BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),

    /* The kernel takes the family as an int, so comparing the low word is the
     * same truncation the syscall itself performs. */
    [L_LOAD_DOMAIN] = BPF_STMT(BPF_LD | BPF_W | BPF_ABS,
                               offsetof(struct seccomp_data, args[0])),
    [L_IS_UNIX] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_UNIX,
                           JT(L_IS_UNIX, L_ALLOW_SOCKET), 0),
    [L_IS_NETLINK] = BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_NETLINK,
                              JT(L_IS_NETLINK, L_ALLOW_SOCKET), 0),
    /* AF_INET, AF_INET6, AF_PACKET and AF_VSOCK all land here. AF_VSOCK
     * matters as much as the others: on a microVM host it is a channel to the
     * hypervisor, not to the internet, so an internet-shaped block misses it.
     */
    [L_DENY_FAMILY] = BPF_STMT(
        BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EAFNOSUPPORT & SECCOMP_RET_DATA)),

    [L_DENY_PERM] = BPF_STMT(BPF_RET | BPF_K,
                             SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
    [L_ALLOW_SOCKET] = BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    [L_KILL_X32] = BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
};

_Static_assert(sizeof(filter) / sizeof(filter[0]) == L_COUNT,
               "filter array and label enum have drifted apart");

/* An fd we opened before the filter went up is an fd the filter cannot take
 * away. Fetching the source uses sockets, so this checks rather than assumes
 * they are gone. */
static int refuse_inherited_sockets(void) {
  DIR *dir = opendir("/proc/self/fd");
  if (dir == NULL) {
    fprintf(stderr, "no-egress: cannot read /proc/self/fd, refusing to guess "
                    "what is open\n");
    return -1;
  }

  int leaked_count = 0;
  int first_leaked = -1;
  struct dirent *entry;

  while ((entry = readdir(dir)) != NULL) {
    int fd = atoi(entry->d_name);
    if (fd <= STDERR_FILENO || fd == dirfd(dir))
      continue;

    int domain = 0;
    socklen_t len = sizeof(domain);
    if (getsockopt(fd, SOL_SOCKET, SO_DOMAIN, &domain, &len) == 0 &&
        (domain == AF_INET || domain == AF_INET6 || domain == AF_PACKET ||
         domain == AF_VSOCK)) {
      if (first_leaked < 0)
        first_leaked = fd;
      leaked_count++;
      continue;
    }

    /* Closed as we go rather than collected first, so there is no array to
     * size and no descriptor left open because the array was full. Closing an
     * unrelated descriptor during readdir is safe; the directory's own one is
     * skipped above. Not a boundary, just hygiene: the compile has no
     * business holding anything the fetch phase opened. */
    close(fd);
  }

  closedir(dir);

  if (leaked_count > 0) {
    fprintf(stderr,
            "no-egress: refusing to run, %d inherited descriptor(s) are "
            "routable sockets, first is fd %d\n",
            leaked_count, first_leaked);
    return -1;
  }

  return 0;
}

/* Proves the filter, in this process, after it is installed.
 *
 * The errno is checked, not merely the failure. A socket call can fail for
 * reasons that have nothing to do with confinement: AF_PACKET is EPERM
 * without CAP_NET_RAW, AF_VSOCK is EAFNOSUPPORT with no transport loaded, and
 * a busy machine can refuse for want of descriptors. Accepting any failure as
 * proof would mean a build whose filter never installed still passes this
 * check on a host that happens to be short of file descriptors. With the
 * filter in force every one of these returns the errno the filter itself
 * carries, before the kernel's own handler is reached, so requiring that
 * exact value is what separates "we denied it" from "it would have failed
 * anyway". */
static int prove_filter(void) {
  static const struct {
    int domain;
    const char *name;
  } routable[] = {
      {AF_INET, "AF_INET"},
      {AF_INET6, "AF_INET6"},
      {AF_PACKET, "AF_PACKET"},
      {AF_VSOCK, "AF_VSOCK"},
  };

  int proven = 1;

  for (size_t i = 0; i < sizeof(routable) / sizeof(routable[0]); i++) {
    errno = 0;
    int fd = socket(routable[i].domain, SOCK_STREAM, 0);
    if (fd >= 0) {
      fprintf(stderr,
              "no-egress: %s socket was still created, the filter did not take "
              "effect\n",
              routable[i].name);
      close(fd);
      proven = 0;
    } else if (errno != EAFNOSUPPORT) {
      fprintf(stderr,
              "no-egress: %s failed with %s, which is not this filter's "
              "refusal, so the filter cannot be shown to be in force\n",
              routable[i].name, strerror(errno));
      proven = 0;
    }
  }

  /* NULL params is a deliberately invalid call: a kernel that would let the
   * ring exist answers EFAULT, a kernel without io_uring answers ENOSYS, and
   * this filter answers EPERM. Only the last one means the ring is closed
   * because we closed it. */
  errno = 0;
  int ring = syscall(__NR_io_uring_setup, 8, NULL);
  if (ring >= 0) {
    fprintf(stderr, "no-egress: io_uring_setup still succeeded, the ring can "
                    "submit socket and connect\n");
    close(ring);
    proven = 0;
  } else if (errno != EPERM) {
    fprintf(stderr,
            "no-egress: io_uring_setup failed with %s rather than this "
            "filter's refusal, so the ring is not provably closed\n",
            strerror(errno));
    proven = 0;
  }

  /* The counterpart to the denials. A filter that broke every socket would
   * pass every assertion above while also breaking things that have nothing
   * to do with egress, so the one permitted family is checked too, and its
   * failure is treated as the filter being wider than it was meant to be. */
  errno = 0;
  int local = socket(AF_UNIX, SOCK_STREAM, 0);
  if (local < 0) {
    fprintf(stderr,
            "no-egress: AF_UNIX is denied too (%s), so this filter is not the "
            "one that was reviewed\n",
            strerror(errno));
    proven = 0;
  } else {
    close(local);
  }

  return proven ? 0 : -1;
}

/* Becomes `spec` (written uid:gid) and refuses to continue unless it worked.
 *
 * This is what closes /proc. The entrypoint holds three signed urls for the
 * whole build because it needs the upload one after the compile, and a
 * same-uid child may read another process's environ, memory and descriptors.
 * PR_SET_DUMPABLE cannot fix that, because execve resets it; a pid namespace
 * cannot, because CLONE_NEWUSER is denied to a container without
 * CAP_SYS_ADMIN. A different uid can, and needs nothing but the privilege we
 * already have at entry: /proc/1/environ then belongs to root and this
 * process is not root any more.
 *
 * Order matters. The groups go before the uid, because dropping the uid first
 * would take away the privilege needed to drop the groups, and setgroups is
 * what removes the supplementary list a stray group membership would
 * otherwise leave behind. */
static int drop_to(const char *spec) {
  char *end = NULL;
  long uid = strtol(spec, &end, 10);
  if (end == NULL || *end != ':') {
    fprintf(stderr, "no-egress: --user wants UID:GID, got %s\n", spec);
    return -1;
  }
  long gid = strtol(end + 1, &end, 10);
  if (end == NULL || *end != '\0' || uid <= 0 || gid <= 0) {
    fprintf(stderr, "no-egress: --user wants a non-root UID:GID, got %s\n",
            spec);
    return -1;
  }

  if (setgroups(0, NULL) != 0 || setgid((gid_t)gid) != 0 ||
      setuid((uid_t)uid) != 0) {
    fprintf(stderr, "no-egress: could not become %s: %s\n", spec,
            strerror(errno));
    return -1;
  }

  /* Checked rather than assumed. A setuid that silently did nothing would
   * leave the compile running as root with everything below it still looking
   * correct. */
  if (getuid() != (uid_t)uid || geteuid() != (uid_t)uid ||
      getgid() != (gid_t)gid || getegid() != (gid_t)gid) {
    fprintf(stderr, "no-egress: still %d:%d after asking for %s\n", getuid(),
            getgid(), spec);
    return -1;
  }

  /* Belt and braces against a future edit passing 0. */
  if (setuid(0) == 0) {
    fprintf(stderr, "no-egress: root is still reachable after dropping to %s\n",
            spec);
    return -1;
  }

  return 0;
}

/* Refuses to continue if this process was handed a capability.
 *
 * This reads /proc/self/environ, not the libc environment, and the
 * difference is the whole point. /proc/<pid>/environ reports the region the
 * kernel recorded at execve, on the initial stack. clearenv() and unsetenv()
 * edit libc's pointer array on the heap and leave that region untouched, so a
 * process that "cleared" its environment still hands the original strings to
 * anyone who can read its /proc entry. Checking the same surface an attacker
 * would read is the only version of this check that means anything.
 *
 * The caller is therefore expected to have made this process clean at exec
 * time, with `env -i`, BEFORE any privilege is dropped. Clearing after the
 * drop would be a window in which an unprivileged process holds the signed
 * urls in a place another process at that uid can read. */
static int refuse_leaked_capabilities(void) {
  int fd = open("/proc/self/environ", O_RDONLY);
  if (fd < 0) {
    fprintf(stderr, "no-egress: cannot read /proc/self/environ, refusing to "
                    "guess what was inherited\n");
    return -1;
  }

  char buffer[8192];
  ssize_t got;
  int leaked = 0;

  /* Entries are NUL separated. A name can straddle a read boundary, so the
   * scan restarts from the last separator each time round. */
  size_t held = 0;
  while ((got = read(fd, buffer + held, sizeof(buffer) - held - 1)) > 0) {
    size_t total = held + (size_t)got;
    buffer[total] = '\0';

    size_t start = 0;
    for (size_t i = 0; i < total; i++) {
      if (buffer[i] != '\0')
        continue;
      if (strncmp(buffer + start, "DOCS_", 5) == 0)
        leaked = 1;
      start = i + 1;
    }

    held = total - start;
    if (held >= sizeof(buffer) - 1)
      held = 0;
    memmove(buffer, buffer + start, held);
  }

  close(fd);

  if (leaked) {
    fprintf(stderr, "no-egress: refusing to run, this process was started "
                    "holding DOCS_ variables. "
                    "The caller must wrap it in `env -i` so the confined side "
                    "never inherits a signed url.\n");
    return -1;
  }

  return 0;
}

int main(int argc, char **argv) {
  int first = 1;
  const char *become = NULL;

  while (first < argc) {
    if (strcmp(argv[first], "--user") == 0 && first + 1 < argc) {
      become = argv[first + 1];
      first += 2;
    } else {
      break;
    }
  }

  if (argc <= first) {
    fprintf(stderr, "usage: no-egress [--user UID:GID] <command> [args...]\n");
    return EXIT_EXEC;
  }

  if (refuse_leaked_capabilities() != 0)
    return EXIT_PRIVILEGE;

  if (become != NULL && drop_to(become) != 0)
    return EXIT_PRIVILEGE;

  /* Refusing to run privileged is the point of the option, so an entrypoint
   * that forgets it does not quietly get a root compile. */
  if (geteuid() == 0) {
    fprintf(stderr,
            "no-egress: refusing to run %s as root; pass --user UID:GID\n",
            argv[first]);
    return EXIT_PRIVILEGE;
  }

  if (refuse_inherited_sockets() != 0)
    return EXIT_INHERITED_SOCKET;

  /* Required to install a filter without CAP_SYS_ADMIN, and worth having on
   * its own: it also stops the compile regaining privilege through a setuid
   * binary. Like the filter, it cannot be turned back off. */
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
    fprintf(stderr, "no-egress: could not set no_new_privs: %s\n",
            strerror(errno));
    return EXIT_NO_NEW_PRIVS;
  }

  struct sock_fprog prog = {
      (unsigned short)(sizeof(filter) / sizeof(filter[0])), filter};

  /* TSYNC is a no-op for a single threaded process and the honest thing to
   * ask for anyway: it refuses rather than leaving a sibling thread outside
   * the filter. The older prctl entry point is the fallback for a kernel
   * without the seccomp syscall. */
  if (syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_TSYNC,
              &prog) != 0 &&
      syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog) != 0 &&
      prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog, 0, 0) != 0) {
    fprintf(stderr, "no-egress: could not install the seccomp filter: %s\n",
            strerror(errno));
    return EXIT_FILTER;
  }

  if (prove_filter() != 0) {
    fprintf(stderr,
            "no-egress: confinement could not be proven, refusing to run %s\n",
            argv[first]);
    return EXIT_NOT_PROVEN;
  }

  fprintf(stderr,
          "no-egress: verified in-process as uid %d, ip and vsock sockets "
          "denied, io_uring denied, no_new_privs set\n",
          getuid());

  execvp(argv[first], &argv[first]);
  fprintf(stderr, "no-egress: could not exec %s: %s\n", argv[first],
          strerror(errno));
  return EXIT_EXEC;
}
