# Set the realm's unmanaged-attribute policy without disturbing the rest
# of the user profile. Keycloak expresses "off" as the absence of the
# key, not as a DISABLED value.
import json, sys

profile = json.load(open(sys.argv[1]))
policy = sys.argv[2]

if policy == "DISABLED":
    profile.pop("unmanagedAttributePolicy", None)
else:
    profile["unmanagedAttributePolicy"] = policy

with open(sys.argv[3], "w") as fh:
    json.dump(profile, fh)
