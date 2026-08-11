locals {
  # The four applications. Every module that fans out per app iterates this, so
  # adding a fifth site is one edit rather than a search for four literals.
  apps = toset(["crystalshards", "crystaldocs", "crystalgigs", "crystalbits"])
}
