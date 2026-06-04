# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For detailed FastMCP documentation, see https://gofastmcp.com.

## Build and Test Commands

```bash
# Install dependencies (creates .venv)
make install

# Run server locally (STDIO mode with hot-reload)
make run-local

# Run all tests
make test
# Or directly:
.venv/bin/pytest tests/ -v

# Run single test file
.venv/bin/pytest tests/test_server.py -v

# Run tests matching pattern
.venv/bin/pytest tests/ -k "test_auth" -v

# Test with cmcp (requires separate terminal)
make test-local
# Or: cmcp ".venv/bin/python -m src.main" tools/list

# Deploy to OpenShift
make deploy PROJECT=my-project

# Deploy to a specific cluster context
make deploy PROJECT=my-project CONTEXT=my-cluster

# Build container for OpenShift (Mac)
podman build --platform linux/amd64 -f Containerfile -t my-mcp:latest .
```

## Architecture Overview

### Component Loading System

The server uses FastMCP 3.x `FileSystemProvider` for automatic component discovery. There is no custom loader -- FastMCP scans directories directly.

1. **Entry point**: `src/main.py` calls `create_server()` then `run_server(mcp)`
2. **Server bootstrap**: `src/core/server.py` creates three `FileSystemProvider` instances that scan `src/tools/`, `src/resources/`, and `src/prompts/`
3. **Standalone decorators**: Components use `@tool`, `@resource`, `@prompt` from `fastmcp.tools`, `fastmcp.resources`, `fastmcp.prompts` respectively -- they do NOT import a shared `mcp` instance
4. **Hot reload**: `FileSystemProvider(path, reload=True)` when `MCP_HOT_RELOAD` is enabled

The `src/core/app.py` module re-exports `create_server()` for convenience (e.g., in tests) but components themselves never import from it.

### Import Convention

**IMPORTANT**: Components use standalone FastMCP decorators. Do NOT import a shared `mcp` instance.

```python
# Correct -- standalone decorators
from fastmcp.tools import tool
from fastmcp.resources import resource
from fastmcp.prompts import prompt
from fastmcp import Context
from fastmcp.exceptions import ToolError

# Incorrect -- these are FastMCP 2.x patterns
from src.core.app import mcp  # WRONG: no shared instance needed
@mcp.tool  # WRONG: use standalone @tool instead
```

For cross-module imports within the project, continue to use the `src.` prefix:

```python
from src.core.logging import get_logger
from src.core.auth import configure_auth
```

The `conftest.py` at project root adds the project directory to `sys.path`, enabling `src.*` imports.

### Module Structure

```
src/
|-- core/
|   |-- app.py        # Re-exports create_server() for convenience
|   |-- server.py     # create_server() + run_server(): providers, middleware, auth
|   |-- auth.py       # JWT auth via FastMCP's JWTVerifier + RemoteAuthProvider
|   +-- logging.py    # Logging configuration
|-- tools/            # Tool implementations (standalone @tool decorator)
|-- resources/        # Resource implementations (standalone @resource decorator, supports subdirectories)
|-- prompts/          # Prompt implementations (standalone @prompt decorator)
+-- middleware/       # Middleware classes (extend fastmcp.server.middleware.Middleware)

manifests/
+-- ecosystem/        # CR templates for MCP ecosystem integration (gateway, catalog, auth)
    |-- httproute.yaml
    |-- mcpserver-registration.yaml
    |-- reference-grant.yaml
    |-- authpolicy.yaml
    +-- virtual-mcp-server.yaml
```

### Transport Modes

- **STDIO** (local): `MCP_TRANSPORT=stdio` -- for cmcp testing
- **HTTP** (OpenShift): `MCP_TRANSPORT=http` -- streamable-http on port 8080

## Testing FastMCP Decorated Functions

FastMCP 3.x standalone decorators (`@tool`, `@resource`, `@prompt`) return the original function with `__fastmcp__` metadata attached. You can call decorated functions directly in tests:

```python
from src.tools.examples.echo import echo

@pytest.mark.asyncio
async def test_echo():
    # Call the function directly -- no .fn access needed
    result = await echo(message="hello", ctx=None)
    assert result == "hello"
```

If a tool uses `ctx` methods (e.g., `await ctx.info(...)`) you will need to provide a mock context or pass `ctx=None` and handle the `AttributeError`. See existing tests in `tests/examples/` for patterns.

## Dependency Management

Dependencies must be listed in BOTH files:
- `pyproject.toml` -- for local `pip install -e .`
- `requirements.txt` -- for container builds

## Adding Components

### Tools (`src/tools/`)

```python
from typing import Annotated
from pydantic import Field
from fastmcp import Context
from fastmcp.tools import tool

@tool(
    annotations={
        "readOnlyHint": True,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
async def my_tool(
    param: Annotated[str, Field(description="Parameter description")],
    ctx: Context = None,
) -> str:
    """Tool description for the LLM."""
    await ctx.info(f"Processing: {param}")
    return f"Result: {param}"
```

### Resources (`src/resources/`)

Supports subdirectories. Files are auto-discovered by `FileSystemProvider`.

```python
from fastmcp.resources import resource

@resource("weather://{city}/current", name="current_weather")
def get_weather(city: str) -> dict:
    """Weather for a city."""
    return {"city": city, "temperature": 22}
```

### Prompts (`src/prompts/`)

```python
from typing import Annotated
from pydantic import Field
from fastmcp.prompts import prompt

@prompt()
def my_prompt(
    query: Annotated[str, Field(description="User query")],
) -> str:
    """Purpose of this prompt."""
    return f"Please answer: {query}"
```

**Type annotations**: Use parameterized types (`dict[str, str]`, `list[str]`) -- never bare `dict` or `list`.

### Middleware (`src/middleware/`)

The server uses FastMCP's built-in `LoggingMiddleware` by default. Custom middleware inherits from the FastMCP base class:

```python
from fastmcp.server.middleware import CallNext, Middleware, MiddlewareContext
from fastmcp.tools.tool import ToolResult
import mcp.types as mt

class MyMiddleware(Middleware):
    async def on_call_tool(
        self,
        context: MiddlewareContext[mt.CallToolRequestParams],
        call_next: CallNext[mt.CallToolRequestParams, ToolResult],
    ) -> ToolResult:
        # Pre-execution logic
        result = await call_next(context)
        # Post-execution logic
        return result
```

### Auth-Protected Components

FastMCP 3.x supports per-component scope checks via the `auth` parameter on decorators. The server-level auth is configured in `src/core/auth.py` using `JWTVerifier` and optionally `RemoteAuthProvider`.

```python
from fastmcp.server.auth import require_scopes
from fastmcp.tools import tool

@tool(auth=require_scopes("admin"))
async def admin_only_tool() -> str:
    """Only accessible with admin scope."""
    return "secret data"
```

## Generator CLI

**IMPORTANT**: `fips-agents` is a global CLI tool installed via pipx. Do NOT use `.venv/bin/fips-agents` -- just run `fips-agents` directly.

```bash
# Generate tool
fips-agents generate tool my_tool --description "Tool description" --async --with-context

# Generate resource
fips-agents generate resource my_resource --uri "data://my-resource" --mime-type "application/json"

# Generate prompt
fips-agents generate prompt my_prompt --description "Prompt description"

# Generate middleware
fips-agents generate middleware my_middleware --description "Middleware description" --async
```

## Prompt Return Types

- `str` -- Simple string (default)
- `PromptMessage` -- Structured message with role
- `list[PromptMessage]` -- Multi-turn conversation

## Pre-deployment

Run `./remove_examples.sh` before first deployment to remove example code and reduce build context size.

## MCP Development Workflow

This template provides slash commands for a structured development workflow:

### Recommended Sequence

```
/plan-tools              -> Creates TOOLS_PLAN.md (planning only, no code)
        |
/create-tools            -> Generates and implements tools in parallel
        |
/exercise-tools          -> Tests ergonomics by role-playing as consuming agent
        |
/deploy-mcp PROJECT=x   -> Deploys to OpenShift (optional, for remote MCP servers)
        |
/integrate-mcp PROJECT=x -> Registers with gateway, catalog, and auth (optional)
```

### Slash Commands

| Command | Purpose |
|---------|---------|
| `/plan-tools` | Read Anthropic's tool design article, create `TOOLS_PLAN.md` |
| `/create-tools` | Generate scaffolds with `fips-agents`, implement in parallel subagents |
| `/exercise-tools` | Role-play as consuming agent, test usability, refine |
| `/deploy-mcp PROJECT=x` | Pre-flight checks, deploy to OpenShift, verify with mcp-test-mcp |
| `/integrate-mcp PROJECT=x` | Register with MCP gateway, catalog, and auth (post-deploy) |

### Tool Design Reference

Before planning tools, the `/plan-tools` command reads:
**https://www.anthropic.com/engineering/writing-tools-for-agents**

Key principles:
- Tools should have clear, descriptive names
- Parameters should be intuitive and well-documented
- Error messages should help agents recover
- Fewer, more powerful tools are better than many simple ones

## Known Issues and Fixes

### File Permission Issue (Auto-Fixed)

**Problem**: Claude Code's Write tool creates files with `600` permissions (owner-only read/write) as a security measure. OpenShift containers run as arbitrary non-root UIDs that need at least `644` (world-readable) permissions.

**Symptoms**: MCP server starts but reports 0 tools loaded:
```
PermissionError: [Errno 13] Permission denied: '/opt/app-root/src/src/core/some_file.py'
```

**Automatic Fixes in Place**:
1. **Containerfile**: `RUN find ./src -name "*.py" -exec chmod 644 {} \;` ensures correct permissions in every build
2. **deploy.sh**: Fixes permissions in the build context and reports how many files were fixed

**Manual Fix** (if needed):
```bash
find src -name "*.py" -perm 600 -exec chmod 644 {} \;
```

**Why This Happens**: This is Claude Code security behavior, not OS behavior. The Write tool intentionally creates files with restrictive permissions to prevent accidental exposure of sensitive content. The Containerfile and deploy.sh fixes ensure this doesn't break OpenShift deployments.

## Testing MCP Servers

### Local Testing with cmcp

```bash
# Start server in STDIO mode
make run-local

# In another terminal, test tools
cmcp ".venv/bin/python -m src.main" tools/list
cmcp ".venv/bin/python -m src.main" tools/call my_tool '{"param": "value"}'
```

### Remote Testing with mcp-test-mcp

After deployment, use `mcp-test-mcp` to verify the server works:

```bash
# List available tools
mcp-test-mcp list_tools --server-url https://<route>/mcp/

# Test a specific tool
mcp-test-mcp test_tool --server-url https://<route>/mcp/ \
  --tool-name my_tool \
  --params '{"param": "value"}'
```

**Important**: If `mcp-test-mcp` tools are not available, ask to have it enabled before testing deployed MCP servers.

## Ecosystem Integration

After deploying with `/deploy-mcp`, use `/integrate-mcp` to register the server with the RHOAI MCP ecosystem. Configuration is stored in `mcp-ecosystem.yaml` (copy from `mcp-ecosystem.yaml.example`).

```bash
# Check integration status
make integrate-check PROJECT=my-mcp-server
```

CR templates live in `manifests/ecosystem/` and use `${PLACEHOLDER}` variables for sed substitution.

Key gotchas:
- `toolPrefix` on MCPServerRegistration is **immutable** once set
- The gateway broker must be restarted after registration changes
- Playground ConfigMap entries must use ClusterIP URLs, not gateway URLs
- Wristband `allowed-tools` must use **unprefixed** tool names

## Deployment Guidelines

### OpenShift Deployment

Each MCP server should deploy to its own OpenShift project to avoid naming collisions.
Pass `CONTEXT` to target a specific cluster without mutating shared kubeconfig state:

```bash
make deploy PROJECT=my-mcp-server
make deploy PROJECT=my-mcp-server CONTEXT=my-cluster
```

### Pre-deployment Checklist

- [ ] All tests pass: `.venv/bin/pytest tests/ -v --ignore=tests/examples/`
- [ ] Permissions fixed: `find src -name "*.py" -perm 600 -exec chmod 644 {} \;`
- [ ] Dependencies in both `pyproject.toml` and `requirements.txt`
- [ ] No hardcoded secrets in source files
- [ ] `.dockerignore` excludes `__pycache__/`, `.venv/`, `tests/`

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `MCP_TRANSPORT` | `stdio` | Transport mode: `stdio` or `http` |
| `MCP_HTTP_HOST` | `127.0.0.1` | HTTP bind address |
| `MCP_HTTP_PORT` | `8000` | HTTP port |
| `MCP_HTTP_PATH` | `/mcp/` | HTTP endpoint path |
| `MCP_LOG_LEVEL` | `INFO` | Logging level |
| `MCP_HOT_RELOAD` | `0` | Enable hot-reload (`FileSystemProvider` reload mode) |
| `MCP_SERVER_NAME` | `fastmcp-unified` | Server name in MCP responses |
| `MCP_AUTH_JWT_ALG` | *(none)* | JWT algorithm (e.g., RS256, HS256). Auth disabled if unset |
| `MCP_AUTH_JWT_SECRET` | *(none)* | Shared secret for HMAC algorithms |
| `MCP_AUTH_JWT_PUBLIC_KEY` | *(none)* | Public key for RSA/EC algorithms |
| `MCP_AUTH_JWT_JWKS_URI` | *(none)* | JWKS endpoint URL (alternative to public key) |
| `MCP_AUTH_JWT_ISSUER` | *(none)* | Expected token issuer |
| `MCP_AUTH_JWT_AUDIENCE` | *(none)* | Expected token audience |
| `MCP_AUTH_REQUIRED_SCOPES` | *(none)* | Comma-separated default required scopes |
| `MCP_AUTH_AUTHORIZATION_SERVERS` | *(none)* | Comma-separated authorization server URLs |
| `MCP_AUTH_BASE_URL` | *(none)* | This server's base URL for OAuth metadata |

## Context Management

When working on this project, use subagents to preserve context:

- **Long terminal output** (builds, deploys): Use `terminal-worker` subagent
- **Parallel tool implementation**: Use `claude-worker` subagents (one per tool)
- **Research tasks**: Use appropriate specialized subagents

This prevents context compression from losing important information about issues encountered.
