# The docs-build Cloud Run Job: the one container that runs untrusted code.
#
# Unlike the four app images, the runtime stage IS the Crystal image rather
# than a bare Alpine with a compiled binary in it. That is not an oversight:
# `crystal docs` expands macros, so it needs the compiler at run time. There is
# nothing of ours to compile here, so there is no build stage.
#
# The tag must track DocsSandbox::DEFAULT_IMAGE in crystalshards. A shard whose
# code uses anything newer than this compiler fails to document for a reason
# that has nothing to do with the shard.
FROM crystallang/crystal:1.21.0-alpine

# curl is the entire client. This container is handed two signed URLs and talks
# to nothing else, so it needs no cloud SDK and holds no credentials. tar
# unpacks the source the launcher prepared.
RUN apk add --no-cache curl tar

# Runs unprivileged. Cloud Run gives per-execution isolation as a platform
# default, so this is defence in depth rather than the boundary itself, but a
# compile that does not need root should not have it.
RUN adduser -D -u 1000 builder

COPY entrypoint.sh /usr/local/bin/docs-build
RUN chmod 0755 /usr/local/bin/docs-build

USER builder
WORKDIR /tmp

ENTRYPOINT ["/usr/local/bin/docs-build"]
