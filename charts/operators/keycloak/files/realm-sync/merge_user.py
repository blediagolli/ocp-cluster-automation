# Merge a desired profile into the user representation Keycloak already
# has. Scalar fields are overwritten from values; attributes are merged
# key by key, so an attribute set outside git survives while the ones
# this chart owns are kept correct.
import json, sys

current = json.load(open(sys.argv[1]))
desired = json.load(open(sys.argv[2]))

attributes = current.get("attributes") or {}
attributes.update(desired.pop("attributes", {}))
current.update(desired)
if attributes:
    current["attributes"] = attributes

with open(sys.argv[3], "w") as fh:
    json.dump(current, fh)
