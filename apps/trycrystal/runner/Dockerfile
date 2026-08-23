# The trycrystal runner image: a Crystal HTTP service that compiles and runs
# a stranger's Crystal on every request.
#
# The runtime stage IS the Crystal image rather than a bare Alpine with a
# binary in it, for the same reason apps/docs-build does it: the product here
# is running the user's code, so the compiler has to be present at run time.
# `crystal run` compiles and links, so cc and the musl toolchain in this image
# are not leftovers, they are the feature. Nothing else is added to it.
#
# The Crystal version is an explicit build argument because the version a
# learner's code runs against is a product decision. Default 1.21.0.
ARG CRYSTAL_VERSION=1.21.0

FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine AS build

# linux-headers is the only extra build dependency, same as docs-build:
# no-egress.c needs linux/seccomp.h, and it must not be in the runtime
# stage so the untrusted compile cannot read our filter out of a header.
RUN apk add --no-cache linux-headers

WORKDIR /src
COPY shard.yml ./
COPY src ./src
COPY sandbox/no-egress.c ./sandbox/no-egress.c
COPY sandbox/warmup.cr ./sandbox/warmup.cr

# Static, so confinement does not depend on a loader finding a shared
# object in a filesystem the compile can write to. -Werror because a
# warning in a seccomp filter is a hole. Vendored from
# apps/docs-build/sandbox/no-egress.c, the filter this project already
# runs against untrusted third-party code.
RUN mkdir -p /out && \
    cc -static -O2 -Wall -Wextra -Werror -o /out/no-egress sandbox/no-egress.c && \
    crystal build --release --no-debug -o /out/trycrystal-runner src/main.cr

# Populate a compiler cache with stdlib objects (JSON, HTTP). Copied into
# each execution's writable scratch at request time; this directory is
# installed read-only in the runtime stage so one submission cannot poison
# the next.
ENV CRYSTAL_CACHE_DIR=/opt/crystal-cache
RUN mkdir -p /opt/crystal-cache && \
    crystal run --no-color sandbox/warmup.cr && \
    chmod -R a+rX /opt/crystal-cache

FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine

# An unprivileged account for the server AND the submissions it runs. The
# server holds no credentials of any kind, so it does not need to outrank the
# code it executes the way docs-build's root supervisor does; what it does
# need is to not be root, which is what this buys. /proc/1/environ is closed
# by the boot-time environment re-exec inside the binary rather than by a uid
# split (see main.cr): execve is the only thing that rewrites what the kernel
# reports there.
RUN adduser -D -u 10001 runner

# Scratch lives outside the root filesystem so this image runs unchanged with
# a read-only root: every write a submission or the compiler performs goes
# under /scratch (its own directory per execution, wiped after), and the
# per-execution HOME, TMPDIR and CRYSTAL_CACHE_DIR are set inside it.
RUN mkdir -p /scratch && chown runner:runner /scratch && chmod 0700 /scratch
VOLUME ["/scratch"]

COPY --from=build /out/trycrystal-runner /usr/local/bin/trycrystal-runner
COPY --from=build /out/no-egress /usr/local/bin/no-egress
COPY --from=build /opt/crystal-cache /opt/crystal-cache
RUN chmod 0755 /usr/local/bin/trycrystal-runner /usr/local/bin/no-egress && \
    chmod -R a+rX /opt/crystal-cache && chmod -R a-w /opt/crystal-cache

ENV RUNNER_SCRATCH_ROOT=/scratch \
    PORT=9292 \
    RUNNER_NO_EGRESS=/usr/local/bin/no-egress \
    RUNNER_CACHE_SEED=/opt/crystal-cache \
    RUNNER_EXEC_MODE=run

# Root-owned binary, unprivileged process: a submission cannot replace the
# thing that supervises the next one.
USER 10001

EXPOSE 9292

# No CMD arguments: the confinement gate reads the environment, and it
# refuses to start unless TRYC_SANDBOX=cloudrun (deployed) or exactly
# ALLOW_UNSAFE=true (developer workstation) is set. An image that boots with
# neither is the failure this design wants.
ENTRYPOINT ["/usr/local/bin/trycrystal-runner"]
