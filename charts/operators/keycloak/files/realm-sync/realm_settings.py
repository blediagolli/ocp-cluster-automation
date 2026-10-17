# Merge the desired realm settings into the representation Keycloak
# already has, rather than PUTting them on their own.
#
# PUT /admin/realms/<realm> takes a whole RealmRepresentation. Sending
# only the handful of fields from values would be read as "everything
# else is unset", so the realm has to be read back first and the changes
# laid on top. Only the keys named in values are touched; anything set in
# the Admin Console that this chart does not manage survives.
import json, sys

current = json.load(open(sys.argv[1]))
desired = json.load(open(sys.argv[2]))

changed = {k: (current.get(k), v) for k, v in desired.items() if current.get(k) != v}
current.update(desired)

with open(sys.argv[3], "w") as fh:
    json.dump(current, fh)

# Printed rather than silent: a no-op run should look like one, and a
# value being changed out from under a realm is worth seeing in the log.
for key in sorted(changed):
    was, now = changed[key]
    print("  %s: %s -> %s" % (key, json.dumps(was), json.dumps(now)))
if not changed:
    print("  already correct")
