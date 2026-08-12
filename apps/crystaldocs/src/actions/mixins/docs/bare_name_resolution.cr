# What a package name means at the bare-name URLs, which are the ones already
# live and indexed.
#
# A name is what a shard calls itself, and two repositories can pick the same
# one, so a bare name is a question that may have any number of answers. The
# registry is the authority on how many. This is the same policy
# `Shards::ShowByName` applies in crystalshards, for the same reason.
#
#   several   -> the choice, spelled out, and nothing is served. This case
#                comes first and overrides everything below it. A row under an
#                ambiguous name cannot be attributed to a repository, so
#                serving it is exactly the failure these URLs have to stop:
#                one shard's documentation read under another shard's name.
#   we hold it -> serve it. The name is unambiguous, the URL is indexed, and
#                the artifact behind it is real. Redirecting instead would
#                send a reader to a canonical URL that has to rebuild from
#                scratch, and for most of these rows the registry does not
#                carry the version they were built at, so it would land on a
#                404 in exchange for nothing.
#   one       -> 301 to that repository's own URL, which is where a version
#                gets registered and a build gets asked for.
#   none      -> the caller's own rows are all there is. That is how the
#                standard library resolves, since it reaches this site through
#                the build pipeline rather than through the registry.
#
# Nil means "the registry has no claim here, answer from your own rows".
module Docs::BareNameResolution
  private def resolve_bare_name(
    name : String,
    held : Bool,
    &build_path : String -> String
  ) : Lucky::Response?
    slugs = CrystalDocs::RegistryPackages.build.slugs_for(name)

    if slugs.size > 1
      html Docs::AmbiguousNamePage, name: name, slugs: slugs
    elsif held
      nil
    elsif slug = slugs.first?
      redirect to: build_path.call(slug), status: 301
    else
      nil
    end
  end
end
