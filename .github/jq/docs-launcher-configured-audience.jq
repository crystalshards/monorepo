# The DOCS_LAUNCHER_AUDIENCE the docs-launcher service is currently configured
# with, or empty if it has none.
#
# Read from the service's own template and nowhere else. A recursive search
# finds the variable in any revision the document happens to carry, including
# ones serving no traffic, so a service whose current template had lost it would
# still appear configured on the strength of an older revision.
#
# Both container shapes are named and concatenated rather than preferred with
# `//`, because an empty array is truthy in jq and would suppress the other.
#
# Distinct values are refused rather than resolved by taking the first: two
# answers to "what does this service verify" is not a state to pick a winner
# from.
[ ((.spec?.template?.spec?.containers? // []) + (.template?.containers? // []))[]
  | (.env? // [])[]
  | select(.name == "DOCS_LAUNCHER_AUDIENCE")
  | .value ]
| map(select(type == "string" and . != "")) | unique
| if length > 1 then "CONFLICT: " + join(", ") else (first // empty) end
