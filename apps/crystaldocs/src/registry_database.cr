# The package registry, which crystalshards owns and is the only writer for.
#
# Two facts this app needs cannot be answered from its own tables: what a
# published version declared as its dependencies, and which Crystal it declared
# support for. Both are recorded when the registry indexes a shard.yml. Reading
# them over a second connection keeps one writer and no copy to drift, at the
# cost of a dependency on another app's schema, which is why every query
# against this database is hand written SQL over a small, stable set of columns
# rather than Avram models mirrored from crystalshards.
#
# This is transitional. Sharing a database couples two apps at the schema
# level, where a crystalshards migration can break this app at runtime with
# nothing in either repo's type system to catch it. The replacement is to
# record the resolved build facts into docs.json at build time, from the
# pinned compiler image and the shard.lock the sandbox has already produced,
# which turns resolution into a lookup and removes the coupling entirely.
class RegistryDatabase < Avram::Database
  # Whether a registry connection was actually configured.
  #
  # Reading the registry is optional: without it, dependency constraints are
  # unknown, and an unknown constraint already has a defined answer, which is
  # to leave the type name as plain text. Callers check this rather than
  # attempting a connection and catching the failure, so an unprovisioned
  # environment costs nothing per page render.
  class_property? configured : Bool = false
end
