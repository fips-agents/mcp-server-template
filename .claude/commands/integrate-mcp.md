---
description: Integrate deployed MCP server into RHOAI ecosystem (gateway, catalog, auth)
---

# Integrate MCP Server

You are integrating a deployed MCP server into the RHOAI MCP ecosystem.  Integration is complete only when tools are discoverable through the gateway — not when the custom resources exist.  Creating CRs is necessary but not sufficient.

**The most common failure mode is assuming the broker auto-discovers new registrations.**  It does not.  The broker deployment must be restarted after changes, and you must verify tool counts through the broker, not just confirm the CRs were created.  Phase 5 is not optional.

## Arguments

- **PROJECT**: (required) The OpenShift project/namespace where the MCP server is deployed.
- **PHASES**: (optional) Comma-separated list of phases to run: `gateway`, `catalog`, `prereqs`, `auth`, or `all` (default: `all`).  Phase 0 (prerequisites check) and Phase 5 (verification) always run regardless of this setting.
- **CONTEXT**: (optional) The OpenShift cluster context to use.  If provided, pass `--context=${CONTEXT}` on every `oc` command.

## Phases

The skill has six phases:

0. **Prerequisites** — verify server is deployed, config exists, auth is valid
1. **Gateway Registration** — HTTPRoute, MCPServerRegistration, ReferenceGrant, Istio labels
2. **Catalog Entry** — catalog ConfigMap, playground ConfigMap
3. **Catalog Prerequisites** — ServiceAccount and ConfigMap for catalog-based deployment
4. **Auth Configuration** — AuthPolicy, VirtualMCPServer (only if auth.enabled)
5. **Verification & Report** — end-to-end check through the gateway

---

## Phase 0: Prerequisites

### 0.1  Config file exists

Check for `mcp-ecosystem.yaml` in the project root.  If missing:

```
STOP: mcp-ecosystem.yaml not found.
Copy mcp-ecosystem.yaml.example to mcp-ecosystem.yaml and customize it for your cluster
before running /integrate-mcp.
```

Read and parse the file.  Validate it has the required top-level keys: `mcp_ecosystem.gateway`, `mcp_ecosystem.catalog`.

### 0.2  OpenShift authentication

```bash
oc whoami
oc whoami --show-server
```

If auth fails, STOP and ask the user to log in with `! oc login ...`.

### 0.3  Server is deployed and responding

The server must already be deployed via `/deploy-mcp`.  Verify:

```bash
oc get deployment mcp-server -n <PROJECT> -o jsonpath='{.status.readyReplicas}'
oc get route mcp-server -n <PROJECT> -o jsonpath='{.spec.host}'
```

If the deployment doesn't exist or has 0 ready replicas, STOP:

```
STOP: No running MCP server found in project <PROJECT>.
Run /deploy-mcp PROJECT=<PROJECT> first.
```

Connect with mcp-test-mcp to verify the server responds:

```
mcp__mcp-test-mcp__connect_to_server(url="https://<route-host>/mcp/")
mcp__mcp-test-mcp__list_tools()
mcp__mcp-test-mcp__disconnect()
```

Record the tool list — you will need it for catalog metadata and auth configuration.

### 0.4  Gateway namespace is accessible

```bash
oc get namespace <gateway_namespace>
oc get gateway <gateway_name> -n <gateway_namespace>
```

If the gateway doesn't exist, STOP and tell the user the gateway must be installed first.

### 0.5  Check for prior integration state

```bash
oc get httproute -n <PROJECT> 2>/dev/null || true
oc get mcpserverregistration -n <PROJECT> 2>/dev/null || true
```

If resources already exist, report what you found and confirm with the user before proceeding.  Pay special attention to an existing MCPServerRegistration — if it has a `toolPrefix` that differs from the config, you MUST stop (see Phase 1.3).

---

## Phase 1: Gateway Registration

Skip this phase if `PHASES` was specified and does not include `gateway`.

### 1.1  Read ecosystem config

Read `mcp-ecosystem.yaml` and extract:
- `gateway.namespace`, `gateway.name`, `gateway.section_name`
- `gateway.hostname_pattern`
- `tool_prefix`

### 1.2  Derive hostname

Determine the cluster domain:

```bash
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
```

Build the hostname by substituting into `hostname_pattern`.  For example, if the pattern is `*.mcp.apps.{cluster_domain}` and the server name is `weather-mcp`, the hostname is `weather-mcp.mcp.apps.<cluster_domain>`.

### 1.3  toolPrefix immutability check

**This is the single most dangerous operation in the integration workflow.**

```bash
oc get mcpserverregistration <server-name> -n <PROJECT> -o jsonpath='{.spec.toolPrefix}' 2>/dev/null || echo "NOT_FOUND"
```

If an MCPServerRegistration already exists with a different `toolPrefix` than what is in `mcp-ecosystem.yaml`:

```
STOP: MCPServerRegistration already exists with toolPrefix="<existing>".
The toolPrefix field is IMMUTABLE (CRD validation rule). It cannot be changed
after creation. Your config specifies toolPrefix="<configured>".

Options:
1. Update mcp-ecosystem.yaml to match the existing prefix
2. Delete the MCPServerRegistration and recreate it (will cause a brief outage)
```

Do NOT proceed.  Do NOT try to patch the field — the CRD will reject it.

### 1.4  Istio namespace labels

The server namespace needs Istio labels for HTTPRoute acceptance:

```bash
oc get namespace <PROJECT> -o jsonpath='{.metadata.labels.istio-discovery}' 2>/dev/null || echo "NOT_SET"
oc get namespace <PROJECT> -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null || echo "NOT_SET"
```

If not already set:

```bash
oc label namespace <PROJECT> istio-discovery=enabled --overwrite
oc label namespace <PROJECT> istio.io/dataplane-mode=ambient --overwrite
```

### 1.5  ReferenceGrant (cross-namespace only)

If `gateway.namespace` differs from `PROJECT`, the gateway needs permission to reference the server's Service:

```bash
sed -e "s|\${GATEWAY_NAMESPACE}|<gateway_ns>|g" \
    -e "s|\${SERVER_NAMESPACE}|<PROJECT>|g" \
    manifests/ecosystem/reference-grant.yaml | oc apply -n <PROJECT> -f -
```

### 1.6  Create HTTPRoute

```bash
sed -e "s|\${SERVER_NAME}|<server-name>|g" \
    -e "s|\${GATEWAY_NAME}|<gateway_name>|g" \
    -e "s|\${GATEWAY_NAMESPACE}|<gateway_ns>|g" \
    -e "s|\${SECTION_NAME}|<section_name>|g" \
    -e "s|\${HOSTNAME}|<derived-hostname>|g" \
    manifests/ecosystem/httproute.yaml | oc apply -n <PROJECT> -f -
```

Verify the HTTPRoute is accepted:

```bash
oc get httproute <server-name> -n <PROJECT> -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
```

If not `True`, check:
- Does the hostname match the gateway listener's wildcard pattern?
- Are the Istio namespace labels applied?
- Is the ReferenceGrant in place (if cross-namespace)?

### 1.7  Create MCPServerRegistration

```bash
sed -e "s|\${SERVER_NAME}|<server-name>|g" \
    -e "s|\${TOOL_PREFIX}|<tool_prefix>|g" \
    manifests/ecosystem/mcpserver-registration.yaml | oc apply -n <PROJECT> -f -
```

### 1.8  Restart gateway broker

The broker does NOT auto-reload when new registrations are created.

```bash
oc rollout restart deployment/mcp-broker -n <gateway_namespace>
oc rollout status deployment/mcp-broker -n <gateway_namespace> --timeout=120s
```

### 1.9  Verify tool discovery

Wait for the broker to discover tools.  Check broker logs:

```bash
oc logs -l app=mcp-broker -n <gateway_namespace> --tail=50 | grep -i "tool\|discover\|register"
```

Report the tool count the broker discovered.  If 0 tools were found after the broker restart:
- Check broker logs for connection errors to the server
- Verify the HTTPRoute is accepted
- Verify the server's `/mcp/` endpoint is reachable from the gateway namespace

---

## Phase 2: Catalog Entry

Skip this phase if `PHASES` was specified and does not include `catalog`.

### 2.1  Build catalog metadata

Generate a catalog entry for this server.  You need:
- Server name and description (from the tool list gathered in Phase 0.3)
- The Route URL (for display)
- The ClusterIP Service URL (for playground — see 2.3)
- Tool count and names

The catalog entry format has strict requirements:
- `artifacts` must be an **array** of `{uri: "oci://..."}` objects — a plain object causes `cannot unmarshal object into []openapi.MCPArtifact`
- `source` must match one of the label names in `model-catalog-default-sources` (e.g., `"Red Hat MCP"` as configured in `mcp-ecosystem.yaml`)

### 2.2  Update catalog ConfigMap

Read the existing ConfigMap:

```bash
oc get configmap <catalog_configmap> -n <catalog_namespace> -o yaml
```

Parse the existing data, add or update this server's entry, and apply:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: <catalog_configmap>
  namespace: <catalog_namespace>
data:
  <server-name>.yaml: |
    <generated catalog entry>
EOF
```

After updating, restart the catalog pod to reload:

```bash
oc rollout restart deployment/model-catalog -n <catalog_namespace>
```

### 2.3  Playground ConfigMap

**Critical: Use the direct ClusterIP Service URL, NOT the gateway URL.**

The Gen AI Studio/Playground cannot forward auth tokens through the gateway (upstream: ogx-ai/ogx#5152, opendatahub-io/ogx-distribution#415).  Register with the ClusterIP URL:

```
http://mcp-server.<PROJECT>.svc:8080/mcp/
```

Read and update the playground ConfigMap:

```bash
oc get configmap <playground_configmap> -n <playground_namespace> -o yaml
```

Add this server's entry with the ClusterIP URL, then apply.

### 2.4  Verify catalog entry

```bash
oc get configmap <catalog_configmap> -n <catalog_namespace> -o jsonpath='{.data.<server-name>\.yaml}'
```

Confirm the entry exists and the `source` field matches the configured `source_label`.

---

## Phase 3: Catalog Prerequisites

Skip this phase if `PHASES` was specified and does not include `prereqs`.

The MCP Lifecycle Operator validates that prerequisite resources exist but does not create them (upstream: kubernetes-sigs/mcp-lifecycle-operator#226).

### 3.1  Create ServiceAccount

```bash
oc create serviceaccount mcp-server -n <PROJECT> --dry-run=client -o yaml | oc apply -f -
```

### 3.2  Create prerequisite ConfigMap

Create a ConfigMap with default runtime configuration as specified in the catalog metadata's `runtimeMetadata.prerequisites`:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: mcp-server-config
  namespace: <PROJECT>
data:
  config.yaml: |
    # Default runtime configuration for catalog-based deployment
    transport: http
    port: 8080
    path: /mcp/
EOF
```

### 3.3  ClusterRoleBindings — human decision

Do NOT create ClusterRoleBindings automatically.  Report to the user:

```
NOTE: ClusterRoleBindings are NOT created automatically.
This is a cluster-scoped security decision that requires human review.
If the catalog deployment needs cluster-level permissions, create them manually.
```

---

## Phase 4: Auth Configuration

Skip this phase entirely if `auth.enabled` is `false` in `mcp-ecosystem.yaml`.
Skip this phase if `PHASES` was specified and does not include `auth`.

### 4.1  Gather auth requirements

Ask the user which Keycloak groups or roles should have access to this server's tools.  If `default_groups` is set in the config, offer those as defaults.

### 4.2  Create AuthPolicy

```bash
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
sed -e "s|\${SERVER_NAME}|<server-name>|g" \
    -e "s|\${CLUSTER_DOMAIN}|${CLUSTER_DOMAIN}|g" \
    -e "s|\${REALM}|<keycloak_realm>|g" \
    manifests/ecosystem/authpolicy.yaml | oc apply -n <PROJECT> -f -
```

### 4.3  Create VirtualMCPServer for tool curation

Build the tool list from Phase 0.3.  **Tool names must be UNPREFIXED** — the broker applies `toolPrefix` internally during matching.  Using prefixed names in the wristband claim causes 0 tools to be returned.

The wristband `allowed-tools` claim must be a `map[string][]string` keyed by MCPServerRegistration name:

```json
{
  "<PROJECT>/<server-name>": ["tool_one", "tool_two", "tool_three"]
}
```

NOT a flat array.  NOT prefixed names.

```bash
sed -e "s|\${SERVER_NAME}|<server-name>|g" \
    -e "s|\${REGISTRATION_NAME}|<server-name>|g" \
    -e "s|\${SERVER_NAMESPACE}|<PROJECT>|g" \
    manifests/ecosystem/virtual-mcp-server.yaml | oc apply -n <PROJECT> -f -
```

After applying, you may need to manually edit the VirtualMCPServer to add specific tool names if the template only has placeholders.

### 4.4  Verify auth

Test that an unauthenticated request is rejected:

```bash
curl -s -o /dev/null -w "%{http_code}" "https://<gateway-hostname>/mcp/"
```

Expected: 401 or 403.

---

## Phase 5: Verification & Report (MANDATORY)

**Do not skip this phase.  Do not summarize before completing it.**

### 5.1  Gateway tool discovery

If Phase 1 ran, verify tools are reachable through the gateway:

```bash
oc logs -l app=mcp-broker -n <gateway_namespace> --tail=20
```

Look for the tool count matching what Phase 0.3 recorded.

### 5.2  Catalog verification

If Phase 2 ran, verify the catalog entry is present and correctly formatted:

```bash
oc get configmap <catalog_configmap> -n <catalog_namespace> -o jsonpath='{.data}' | grep <server-name>
```

### 5.3  Auth verification

If Phase 4 ran, verify the AuthPolicy is enforced and the VirtualMCPServer is configured.

### 5.4  Summary report

After all verification passes, produce:

```markdown
## Integration Summary

**Project**: <PROJECT>
**Gateway**: <gateway_name> in <gateway_namespace>
**Status**: SUCCESS

### Gateway Registration
- [x] HTTPRoute created and accepted
- [x] MCPServerRegistration created (toolPrefix: "<prefix>")
- [x] ReferenceGrant created (cross-namespace: yes/no)
- [x] Istio labels applied
- [x] Broker restarted and discovered N tools

### Catalog Entry
- [x] Catalog ConfigMap updated in <catalog_namespace>
- [x] Playground ConfigMap updated (ClusterIP URL)
- [x] Catalog pod restarted

### Prerequisites
- [x] ServiceAccount created
- [x] Config ConfigMap created
- [ ] ClusterRoleBindings — manual step (not auto-created)

### Auth (if enabled)
- [x] AuthPolicy created
- [x] VirtualMCPServer created with N tools (unprefixed)
- [x] Unauthenticated access rejected

### Configuration Reference
- Gateway hostname: <hostname>
- Direct route: https://<route-host>/mcp/
- ClusterIP URL: http://mcp-server.<PROJECT>.svc:8080/mcp/
- Tool prefix: <prefix>
```

If anything is incomplete, the status is NOT SUCCESS.  Use INCOMPLETE or FAILED.

---

## Important Guidelines

- **Phase 5 is not optional.**  CRs existing is necessary but not sufficient.  The broker must have discovered your tools.
- **Namespace via `-n`, not `oc project`.**  Multiple simultaneous Claude Code sessions on the same cluster would collide otherwise.
- **Pass `--context` on every `oc` command** if a CONTEXT argument was provided.
- **toolPrefix is immutable.**  Always check before creating an MCPServerRegistration.
- **Broker must be restarted** after MCPServerRegistration changes.
- **Catalog pod must be restarted** after ConfigMap changes.
- **Playground uses ClusterIP URL**, not gateway URL — the Playground cannot forward auth tokens.
- **Tool names in wristband must be unprefixed** — the broker applies the prefix internally.
- **Use terminal-worker for long-running commands** like broker restarts and rollout waits.

---

## Error Recovery

### HTTPRoute not accepted (NoMatchingListenerHostname)

- The hostname must match the gateway listener's wildcard pattern
- Check: `oc get gateway <name> -n <gateway_ns> -o yaml` and look at `listeners[].hostname`
- Verify the Istio namespace labels are applied

### Broker discovers 0 tools after restart

- Check broker logs for connection errors: `oc logs -l app=mcp-broker -n <gateway_ns> --tail=100`
- Verify the server's `/mcp/` endpoint is reachable from the gateway namespace
- Verify the HTTPRoute has `Accepted: True` status
- Check the MCPServerRegistration's `serverPath` matches the server's endpoint

### Catalog entry not visible in dashboard

- The `source` field must match one of the label names in `model-catalog-default-sources`
- The `artifacts` field must be an array, not a plain object
- The catalog pod must be restarted after ConfigMap changes

### VirtualMCPServer returns 0 tools

- Tool names in the wristband `allowed-tools` claim must be **unprefixed**
- The claim format must be `map[string][]string` keyed by `"namespace/registration-name"`
- `x-mcp-virtualserver` header routing doesn't work (ext_proc runs before Kuadrant Wasm plugin) — use wristband claims instead

### toolPrefix mismatch

- `toolPrefix` is immutable on MCPServerRegistration (CRD validation rule)
- To change it: delete the registration, restart the broker, create a new registration with the new prefix
- All downstream consumers (wristband claims, VirtualMCPServer) must be updated to match
