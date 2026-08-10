# Isolation policy for untrusted documentation builds.
#
# THREAT: `crystal docs` executes compile-time macros, so building documentation
# for a third-party shard runs that shard author's code inside our build. This
# policy is the network containment for that code execution.
#
# Data path (why this is not a pure deny-all): the build Job moves data through
# MinIO, not the network stack of the untrusted container. A Job pod runs three
# containers in order: a trusted "fetch" initContainer holding scoped MinIO
# credentials downloads the source tarball to a shared emptyDir, an UNTRUSTED
# "build" initContainer with NO environment at all runs `crystal docs`, and a
# trusted "upload" main container holding scoped MinIO credentials pushes the
# generated docs. Environment is per-container while network is per-pod, so the
# untrusted step can open a socket to MinIO but has no credentials; MinIO
# rejects unauthenticated requests and the blast radius is "can connect to a
# port that refuses it".
resource "kubernetes_network_policy" "docs_sandbox_isolation" {
  metadata {
    name      = "docs-sandbox-isolation"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]

    # Ingress: NO rules at all. Nothing may initiate a connection to a build
    # pod. The absence of rules here is deliberate, do not add any.

    # Egress rule 1 of 2: MinIO only. The trusted fetch/upload containers stage
    # source tarballs and generated docs through the MinIO tenant in the
    # infrastructure namespace. The untrusted build container shares the pod
    # network but carries no credentials, so this rule is useless to it.
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "infrastructure"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "9000"
      }
    }

    # Egress rule 2 of 2: DNS to kube-dns ONLY. The existing application code
    # resolves MinIO by service name (shared-storage-hl.infrastructure.svc.cluster.local),
    # not by ClusterIP, so name resolution is required. It is scoped to GKE's
    # kube-dns pods (k8s-app=kube-dns in kube-system) and nothing else.
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # There is deliberately NO other egress: no 0.0.0.0/0, no 443, no cluster
    # or API server access. That absence is the whole point of this policy.
    # Do not "helpfully" add general DNS or HTTPS egress back; a build pod with
    # internet egress turns compile-time macro execution into credential
    # exfiltration.
  }
}
