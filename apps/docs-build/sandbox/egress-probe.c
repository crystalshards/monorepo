/*
 * egress-probe: ask the kernel, right here, whether this process can obtain
 * something that reaches off the machine.
 *
 *   egress-probe --expect-open     exit 0 when at least one path is usable
 *   egress-probe --expect-closed   exit 0 when every path is refused
 *
 * Both directions exist because only the pair means anything. Run under
 * no-egress, every probe fails; that on its own also happens when the probe
 * is broken, when the binary is missing, or when the machine has no network
 * at all. Running the same probe in the fetch phase, where it must succeed,
 * is what turns the second result into evidence.
 *
 * This deliberately measures the syscall, not a URL. Whether some host
 * answers is a fact about the internet on the day the build ran. Whether this
 * process can create a routable socket is a fact about the confinement, and
 * it is the same answer every time.
 */
#include <errno.h>
#include <linux/io_uring.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef AF_VSOCK
#define AF_VSOCK 40
#endif

#ifndef __X32_SYSCALL_BIT
#define __X32_SYSCALL_BIT 0x40000000U
#endif

static int report(const char *name, int open, const char *detail) {
  fprintf(stderr, "egress-probe: %-22s %s%s%s\n", name, open ? "OPEN" : "blocked",
          detail && *detail ? " " : "", detail ? detail : "");
  return open;
}

static int probe_family(const char *name, int domain) {
  int fd = socket(domain, SOCK_STREAM, 0);
  if (fd >= 0) {
    close(fd);
    return report(name, 1, "socket() returned a descriptor");
  }
  return report(name, 0, strerror(errno));
}

/* io_uring can create and connect a socket from inside the ring, so a filter
 * that only watches socket(2) never sees it happen. Measured, not assumed:
 * this submits a real IORING_OP_SOCKET and reports what came back. */
static int probe_io_uring(void) {
  struct io_uring_params p;
  memset(&p, 0, sizeof(p));

  int ring = syscall(__NR_io_uring_setup, 8, &p);
  if (ring < 0) return report("io_uring", 0, strerror(errno));

  size_t sring_sz = p.sq_off.array + p.sq_entries * sizeof(unsigned);
  size_t cring_sz = p.cq_off.cqes + p.cq_entries * sizeof(struct io_uring_cqe);
  void *sq = mmap(0, sring_sz, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, ring, IORING_OFF_SQ_RING);
  void *cq = mmap(0, cring_sz, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, ring, IORING_OFF_CQ_RING);
  struct io_uring_sqe *sqes = mmap(0, p.sq_entries * sizeof(struct io_uring_sqe), PROT_READ | PROT_WRITE,
                                   MAP_SHARED | MAP_POPULATE, ring, IORING_OFF_SQES);

  if (sq == MAP_FAILED || cq == MAP_FAILED || sqes == MAP_FAILED) {
    close(ring);
    /* The ring exists, which is the part that matters, so this is reported as
     * open rather than quietly passing. */
    return report("io_uring", 1, "ring created, could not map it to finish the submission");
  }

  unsigned *sq_tail = (unsigned *)((char *)sq + p.sq_off.tail);
  unsigned *sq_mask = (unsigned *)((char *)sq + p.sq_off.ring_mask);
  unsigned *sq_array = (unsigned *)((char *)sq + p.sq_off.array);
  unsigned *cq_head = (unsigned *)((char *)cq + p.cq_off.head);
  unsigned *cq_tail = (unsigned *)((char *)cq + p.cq_off.tail);
  unsigned *cq_mask = (unsigned *)((char *)cq + p.cq_off.ring_mask);
  struct io_uring_cqe *cqes = (struct io_uring_cqe *)((char *)cq + p.cq_off.cqes);

  unsigned tail = *sq_tail;
  unsigned index = tail & *sq_mask;
  struct io_uring_sqe *sqe = &sqes[index];
  memset(sqe, 0, sizeof(*sqe));
  sqe->opcode = 45; /* IORING_OP_SOCKET */
  sqe->fd = AF_INET;
  sqe->off = SOCK_STREAM;
  sq_array[index] = index;
  __atomic_store_n(sq_tail, tail + 1, __ATOMIC_RELEASE);

  int entered = syscall(__NR_io_uring_enter, ring, 1, 1, IORING_ENTER_GETEVENTS, NULL, 0);
  if (entered < 0) {
    close(ring);
    return report("io_uring", 1, "ring created, submission refused");
  }

  int open = 0;
  const char *detail = "ring created, no completion";
  if (*cq_head != __atomic_load_n(cq_tail, __ATOMIC_ACQUIRE)) {
    struct io_uring_cqe *cqe = &cqes[*cq_head & *cq_mask];
    if (cqe->res >= 0) {
      close(cqe->res);
      open = 1;
      detail = "IORING_OP_SOCKET produced an AF_INET descriptor";
    } else {
      open = 1;
      detail = "ring created, IORING_OP_SOCKET refused";
    }
  }

  close(ring);
  return report("io_uring", open, detail);
}

/* x32 numbers its syscalls with a high bit set while still reporting
 * AUDIT_ARCH_X86_64, so an equality test on the syscall number can be walked
 * straight past. Forked, because a filter that catches this ends the process
 * rather than returning an error, and the probe has more to report. */
static int probe_x32_socket(void) {
  pid_t pid = fork();
  if (pid < 0) return report("x32 socket number", 0, strerror(errno));

  if (pid == 0) {
    long fd = syscall(__NR_socket | __X32_SYSCALL_BIT, AF_INET, SOCK_STREAM, 0);
    _exit(fd >= 0 ? 0 : 1);
  }

  int status = 0;
  if (waitpid(pid, &status, 0) < 0) return report("x32 socket number", 0, strerror(errno));

  if (WIFSIGNALED(status)) {
    static char detail[64];
    snprintf(detail, sizeof(detail), "child killed by signal %d", WTERMSIG(status));
    return report("x32 socket number", 0, detail);
  }

  int got_fd = WIFEXITED(status) && WEXITSTATUS(status) == 0;
  return report("x32 socket number", got_fd, got_fd ? "socket created through the x32 number" : "refused");
}

int main(int argc, char **argv) {
  int expect_open;

  if (argc == 2 && strcmp(argv[1], "--expect-open") == 0) {
    expect_open = 1;
  } else if (argc == 2 && strcmp(argv[1], "--expect-closed") == 0) {
    expect_open = 0;
  } else {
    fprintf(stderr, "usage: egress-probe --expect-open|--expect-closed\n");
    return 2;
  }

  int open_paths = 0;
  open_paths += probe_family("AF_INET socket", AF_INET);
  open_paths += probe_family("AF_INET6 socket", AF_INET6);
  open_paths += probe_family("AF_PACKET socket", AF_PACKET);
  open_paths += probe_family("AF_VSOCK socket", AF_VSOCK);
  open_paths += probe_io_uring();
  open_paths += probe_x32_socket();

  if (expect_open) {
    if (open_paths > 0) return 0;
    fprintf(stderr, "egress-probe: expected the network to be reachable here and no path is open\n");
    return 1;
  }

  if (open_paths == 0) return 0;
  fprintf(stderr, "egress-probe: %d path(s) off this machine are still open\n", open_paths);
  return 1;
}
