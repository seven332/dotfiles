#!/bin/bash
set -e

# Install Node.js if not already installed
if ! command -v node &> /dev/null; then
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Install pnpm if not already installed
if ! command -v pnpm &> /dev/null; then
    echo "Installing pnpm..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
fi

# Setup pnpm global bin directory
pnpm setup
source ~/.bashrc 2>/dev/null || true

# Install Claude Code globally
echo "Installing Claude Code..."
pnpm add -g @anthropic-ai/claude-code

echo "Setup complete!"
