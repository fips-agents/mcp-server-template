.PHONY: install run-local test test-local lint deploy integrate-check clean help

# Variables
VENV ?= .venv
PYTHON ?= python3
PROJECT ?= mcp-demo
CONTEXT ?=

# Default target
help:
	@echo "MCP Server Template - Available Commands"
	@echo "========================================"
	@echo "Local Development:"
	@echo "  make install     - Install dependencies"
	@echo "  make run-local   - Run server locally (STDIO mode)"
	@echo "  make test-local  - Test with cmcp locally"
	@echo "  make test        - Run pytest suite"
	@echo "  make lint        - Run ruff linter"
	@echo ""
	@echo "OpenShift Deployment:"
	@echo "  make deploy          - Deploy to OpenShift (PROJECT=name [CONTEXT=name])"
	@echo "  make integrate-check - Verify ecosystem integration (PROJECT=name [CONTEXT=name])"
	@echo "  make clean           - Remove from OpenShift (PROJECT=name [CONTEXT=name])"
	@echo ""
	@echo "Other:"
	@echo "  make help        - Show this help message"

# Install dependencies
install:
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements.txt
	@echo "✅ Installation complete. Activate with: source $(VENV)/bin/activate"

# Run locally with STDIO for cmcp testing
run-local: install
	@echo "Starting MCP server in STDIO mode..."
	@echo "Test with: cmcp '$(VENV)/bin/python -m src.main' tools/list"
	MCP_TRANSPORT=stdio MCP_HOT_RELOAD=1 $(VENV)/bin/python -m src.main

# Test locally with cmcp
test-local:
	@echo "Testing MCP server with cmcp..."
	@echo "Listing tools..."
	@cmcp "$(VENV)/bin/python -m src.main" tools/list || echo "cmcp not installed. Install with: pip install cmcp"

# Run pytest tests
test:
	$(VENV)/bin/pytest tests/ -v

# Run ruff linter
lint:
	@$(VENV)/bin/pip install -q ruff 2>/dev/null || true
	$(VENV)/bin/ruff check src/ tests/

# Deploy to OpenShift
deploy:
	@echo "Deploying to OpenShift project: $(PROJECT)"
	./deploy.sh $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),)

# Check ecosystem integration status (read-only)
integrate-check:
	@echo "Checking MCP ecosystem integration for project: $(PROJECT)"
	@echo ""
	@echo "--- HTTPRoute ---"
	@oc get httproute -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) 2>/dev/null || echo "  No HTTPRoute found"
	@echo ""
	@echo "--- MCPServerRegistration ---"
	@oc get mcpserverregistration -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) 2>/dev/null || echo "  No MCPServerRegistration found"
	@echo ""
	@echo "--- ReferenceGrant ---"
	@oc get referencegrant -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) 2>/dev/null || echo "  No ReferenceGrant found"
	@echo ""
	@echo "--- AuthPolicy ---"
	@oc get authpolicy -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) 2>/dev/null || echo "  No AuthPolicy found"
	@echo ""
	@echo "--- VirtualMCPServer ---"
	@oc get virtualmcpserver -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) 2>/dev/null || echo "  No VirtualMCPServer found"

# Clean up OpenShift deployment
clean:
	@echo "Cleaning up OpenShift project: $(PROJECT)"
	@oc delete -f openshift.yaml -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) --ignore-not-found=true || echo "Not deployed or already cleaned"

# Development shortcuts
dev: run-local
