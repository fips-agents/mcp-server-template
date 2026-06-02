#!/bin/bash
#
# Remove all example content from the MCP server project
#
# This script removes:
# - Example tools, resources, prompts, and middleware
# - Example tests
# - Example documentation
#
# This is recommended to prevent examples from cluttering your AI assistant's
# context window when working on your actual implementation.
#

set -e

echo "🧹 Removing example content..."

# Remove example directories
if [ -d "src/tools/examples" ]; then
    rm -rf src/tools/examples
    echo "✓ Removed src/tools/examples"
fi

if [ -d "src/resources/examples" ]; then
    rm -rf src/resources/examples
    echo "✓ Removed src/resources/examples"
fi

# Remove example resource subdirectories (travel theme examples)
if [ -d "src/resources/country_profiles" ]; then
    rm -rf src/resources/country_profiles
    echo "✓ Removed src/resources/country_profiles"
fi

if [ -d "src/resources/checklists" ]; then
    rm -rf src/resources/checklists
    echo "✓ Removed src/resources/checklists"
fi

if [ -d "src/resources/emergency_protocols" ]; then
    rm -rf src/resources/emergency_protocols
    echo "✓ Removed src/resources/emergency_protocols"
fi

if [ -d "src/prompts/examples" ]; then
    rm -rf src/prompts/examples
    echo "✓ Removed src/prompts/examples"
fi

if [ -d "src/middleware/examples" ]; then
    rm -rf src/middleware/examples
    echo "✓ Removed src/middleware/examples"
fi

# Remove example tests
if [ -d "tests/examples" ]; then
    rm -rf tests/examples
    echo "✓ Removed tests/examples"
fi

if [ -f "tests/test_server_e2e.py" ]; then
    rm -f tests/test_server_e2e.py
    echo "✓ Removed tests/test_server_e2e.py"
fi

# Remove cache files
echo ""
echo "🧹 Cleaning cache files..."

if [ -d ".mypy_cache" ]; then
    rm -rf .mypy_cache
    echo "✓ Removed .mypy_cache"
fi

if [ -d ".pytest_cache" ]; then
    rm -rf .pytest_cache
    echo "✓ Removed .pytest_cache"
fi

if [ -d ".ruff_cache" ]; then
    rm -rf .ruff_cache
    echo "✓ Removed .ruff_cache"
fi

find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null && echo "✓ Removed __pycache__ directories" || true
find . -name '*.pyc' -delete 2>/dev/null && echo "✓ Removed .pyc files" || true

echo ""
echo "📊 Final src/ size:"
du -sh src/

echo ""
echo "✅ All examples and cache files removed!"
echo ""
echo "Your MCP server now has a clean slate."
echo "Use 'fips-agents generate' to create new components."
