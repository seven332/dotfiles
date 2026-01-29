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

# Install Powerlevel10k theme
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
fi

# Set Powerlevel10k as the theme in .zshrc
if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$HOME/.zshrc"; then
        echo "Setting Powerlevel10k as zsh theme..."
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
    fi
fi

# Copy p10k configuration
if [ -f "/home/vscode/dotfiles/.p10k.zsh" ]; then
    echo "Copying Powerlevel10k configuration..."
    cp /home/vscode/dotfiles/.p10k.zsh "$HOME/.p10k.zsh"

    # Add p10k config loading to .zshrc if not already present
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q 'source ~/.p10k.zsh' "$HOME/.zshrc"; then
            echo "" >> "$HOME/.zshrc"
            echo "# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh." >> "$HOME/.zshrc"
            echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> "$HOME/.zshrc"
        fi
    fi
fi

# Configure SSH agent forwarding
if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q 'SSH agent forwarding' "$HOME/.zshrc"; then
        echo "" >> "$HOME/.zshrc"
        echo "# SSH agent forwarding" >> "$HOME/.zshrc"
        echo 'if [ -z "$SSH_AUTH_SOCK" ]; then' >> "$HOME/.zshrc"
        echo '    eval "$(ssh-agent -s)" > /dev/null' >> "$HOME/.zshrc"
        echo '    ssh-add ~/.ssh/id_* 2>/dev/null' >> "$HOME/.zshrc"
        echo 'fi' >> "$HOME/.zshrc"
    fi
fi

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Setting zsh as default shell..."
    sudo chsh -s $(which zsh) $USER
fi

# Install Go if not already installed
if ! command -v go &> /dev/null; then
    echo "Installing Go..."
    GO_VERSION=$(curl -sL https://go.dev/VERSION?m=text | head -1)
    wget -q "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "${GO_VERSION}.linux-amd64.tar.gz"
    rm "${GO_VERSION}.linux-amd64.tar.gz"
fi

# Add Go to PATH for current script and persist to .zshrc
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q '/usr/local/go/bin' "$HOME/.zshrc"; then
        echo 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"' >> "$HOME/.zshrc"
    fi
fi

# Install Axiom CLI
if ! command -v axiom &> /dev/null; then
    echo "Installing Axiom CLI..."
    go install github.com/axiomhq/cli/cmd/axiom@latest
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
export SHELL=$(which zsh)
pnpm setup
source ~/.zshrc 2>/dev/null || true

# Install Claude Code
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

echo "Setup complete!"
