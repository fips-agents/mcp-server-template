.PHONY: install run-local test test-local lint deploy clean help

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
	@echo "  make deploy      - Deploy to OpenShift (PROJECT=name [CONTEXT=name])"
	@echo "  make clean       - Remove from OpenShift (PROJECT=name [CONTEXT=name])"
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

# Clean up OpenShift deployment
clean:
	@echo "Cleaning up OpenShift project: $(PROJECT)"
	@oc delete -f openshift.yaml -n $(PROJECT) $(if $(CONTEXT),--context=$(CONTEXT),) --ignore-not-found=true || echo "Not deployed or already cleaned"

# Development shortcuts
dev: run-local
