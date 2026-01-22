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

# Install Claude Code
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

echo "Setup complete!"
