# Splice client secrets from the environment into the partialImport body.
# Values come from the Vault-backed Secret via env vars, so nothing secret
# is read from disk or passed on a command line.
import json, os, sys

payload = json.load(open(sys.argv[1]))
env_by_client = json.loads(os.environ["CLIENT_ENV_MAP"])

for client in payload.get("clients", []):
    var = env_by_client.get(client["clientId"])
    if not var:
        continue
    value = os.environ.get(var)
    if not value:
        sys.exit("missing %s - is the realm credentials Secret populated?" % var)
    client["secret"] = value

with open(sys.argv[2], "w") as fh:
    json.dump(payload, fh)
