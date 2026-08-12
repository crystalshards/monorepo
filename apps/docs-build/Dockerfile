# The docs-build Cloud Run Job: the one container that runs untrusted code.
#
# Unlike the four app images, the runtime stage IS the Crystal image rather
# than a bare Alpine with a compiled binary in it. That is not an oversight:
# `crystal docs` expands macros, so it needs the compiler at run time. There is
# nothing of ours to compile here except the three sandbox helpers below.
#
# The tag must track DocsSandbox::DEFAULT_IMAGE in crystalshards. A shard whose
# code uses anything newer than this compiler fails to document for a reason
# that has nothing to do with the shard.
FROM crystallang/crystal:1.21.0-alpine AS sandbox

# The kernel uapi headers are the only build dependency; the Crystal image
# already carries cc because linking a Crystal program needs it. They are
# installed here and not in the runtime stage, so the untrusted compile does
# not get a copy of linux/seccomp.h to read our filter out of.
RUN apk add --no-cache linux-headers

WORKDIR /sandbox
COPY sandbox/no-egress.c sandbox/egress-probe.c ./

# Static, so the confinement does not depend on a loader finding a shared
# object in a filesystem the compile phase can write to. -Werror because a
# warning in a seccomp filter is a hole.
RUN set -eux; \
  for tool in no-egress egress-probe; do \
  cc -static -O2 -Wall -Wextra -Werror -o "/out-$tool" "$tool.c"; \
  done

FROM crystallang/crystal:1.21.0-alpine

# curl is the entire client. This container is handed signed URLs and talks to
# nothing else, so it needs no cloud SDK and holds no credentials. tar unpacks
# the source the launcher prepared.
RUN apk add --no-cache curl tar

# The account the compile becomes. The entrypoint itself stays root, which is
# the only way this container can keep its signed urls away from the code it
# compiles: a same-uid child may read another process's environ, memory and
# descriptors out of /proc, and nothing available to an unprivileged
# container closes that. PR_SET_DUMPABLE is reset by execve and a pid
# namespace needs CLONE_NEWUSER, which runtimes deny without CAP_SYS_ADMIN.
# A different uid needs none of that, so root supervises and no-egress drops
# to this account before any shard code runs.
#
# Nothing the shard can influence runs as root: the source tarball is
# unpacked as builder and the compile runs as builder. Root runs curl against
# the two urls it was given, and the shell that sequences them.
#
# Being root-owned is also what stops the compile overwriting curl, crystal
# or the helpers below, which is what makes the upload after the compile safe
# to run.
RUN adduser -D -u 1000 builder

COPY --from=sandbox /out-no-egress /usr/local/bin/no-egress
COPY --from=sandbox /out-egress-probe /usr/local/bin/egress-probe
COPY entrypoint.sh /usr/local/bin/docs-build
RUN chmod 0755 /usr/local/bin/no-egress /usr/local/bin/egress-probe \
  /usr/local/bin/docs-build

# No USER line. See the comment on the builder account: the supervisor has to
# outrank the compile for /proc to be closed to it, and no-egress refuses to
# exec anything as root, so a missing --user is a failed build rather than a
# privileged one.
WORKDIR /tmp

ENTRYPOINT ["/usr/local/bin/docs-build"]
