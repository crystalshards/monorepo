# Every OIDC audience the docs-launcher service actually accepts, space
# separated, or "UNPARSEABLE: <raw>" when the annotation is present but is not
# the JSON it is supposed to be.
#
# Where these live depends on which representation the CLI returns. On the v1
# (Knative) shape gcloud gives by default they are a JSON-encoded string in a
# SERVICE-level annotation; on v2 they are a plain array at the top level.
#
# Only service-level locations are read. A revision template can carry its own
# copy of the annotation, and that copy describes what a future revision would
# declare, not what the service accepts now. Matching it would let a service
# that rejects every token pass, which is the one thing this must never do.
#
# An unparseable annotation is reported as itself rather than folded into the
# empty result. Both would stop the release, but "the service accepts nothing"
# and "we could not read what it accepts" send whoever is holding the pager to
# different places, and this guard has already cost one release by reporting
# something it had not actually established.
def raw:
  (.metadata?.annotations?["run.googleapis.com/custom-audiences"]? // null);
def annotated:
  (raw // "[]") | (try fromjson catch "unparseable");
def declared:
  (.customAudiences? // []);
if (annotated == "unparseable") then
  "UNPARSEABLE: " + raw
else
  (annotated + declared)
  | map(select(type == "string"))
  | unique | join(" ")
end
