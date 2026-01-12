#!/bin/bash
set -e

# Install zsh if not already installed
if ! command -v zsh &> /dev/null; then
    echo "Installing zsh..."
    sudo apt-get update
    sudo apt-get install -y zsh
fi

# Install Oh My Zsh if not already installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Setting zsh as default shell..."
    sudo chsh -s $(which zsh) $USER
fi

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
