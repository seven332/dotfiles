#!/bin/bash
set -e

# Set timezone from host (passed via --remote-env TZ=...)
if [ -n "${TZ:-}" ]; then
    echo "Setting timezone to $TZ..."
    sudo ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" | sudo tee /etc/timezone > /dev/null
fi

# Configure Ubuntu apt sources
configure_ubuntu_sources() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    fi

    if [ "${ID:-}" != "ubuntu" ]; then
        return
    fi

    local apt_arch archive_uri security_uri
    apt_arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case $apt_arch in
        amd64|x86_64)
            archive_uri="https://us.archive.ubuntu.com/ubuntu"
            security_uri="https://security.ubuntu.com/ubuntu"
            ;;
        arm64|aarch64)
            archive_uri="https://ports.ubuntu.com/ubuntu-ports"
            security_uri="$archive_uri"
            ;;
        *)
            echo "Skipping Ubuntu apt source switch for unsupported architecture: $apt_arch"
            return
            ;;
    esac

    local source_files=()
    if [ -f /etc/apt/sources.list ]; then
        source_files+=("/etc/apt/sources.list")
    fi
    if [ -d /etc/apt/sources.list.d ]; then
        while IFS= read -r -d '' source_file; do
            source_files+=("$source_file")
        done < <(find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) -print0)
    fi
    if [ ${#source_files[@]} -eq 0 ]; then
        return
    fi

    echo "Configuring Ubuntu apt sources..."
    sudo sed -i -E \
        -e "s|https?://([^[:space:]/]+\.)?archive\.ubuntu\.com/ubuntu/?|${archive_uri}|g" \
        -e "s|https?://security\.ubuntu\.com/ubuntu/?|${security_uri}|g" \
        -e "s|https?://ports\.ubuntu\.com/ubuntu-ports/?|${archive_uri}|g" \
        "${source_files[@]}"
}
configure_ubuntu_sources

# Install essential packages
echo "Installing essential packages..."
sudo apt-get update
sudo apt-get install -y zsh make htop jq expect

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
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) GO_ARCH="amd64" ;;
        aarch64|arm64) GO_ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    wget -q "https://go.dev/dl/${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    rm "${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
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

# Install Codex
if ! command -v codex &> /dev/null; then
    echo "Installing Codex..."
    curl -fsSL https://github.com/openai/codex/releases/latest/download/install.sh | sh
fi

# Install codex-switch
mkdir -p "$HOME/.local/bin"
CODEX_SWITCH_BIN="$HOME/.local/bin/codex-switch"
if [ ! -x "$CODEX_SWITCH_BIN" ]; then
    echo "Installing codex-switch..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) CODEX_SWITCH_ASSET="codex-switch-x86_64-unknown-linux-musl" ;;
        aarch64|arm64) CODEX_SWITCH_ASSET="codex-switch-aarch64-unknown-linux-musl" ;;
        *) echo "Unsupported architecture for codex-switch: $ARCH"; exit 1 ;;
    esac
    CODEX_SWITCH_TMP=$(mktemp)
    curl -fsSL -o "$CODEX_SWITCH_TMP" "https://github.com/seven332/codex-switch/releases/latest/download/${CODEX_SWITCH_ASSET}"
    install -m 0755 "$CODEX_SWITCH_TMP" "$CODEX_SWITCH_BIN"
    rm -f "$CODEX_SWITCH_TMP"
fi

# Mirror Claude commands into Codex layout for the workspace project
codex_claude_compat_init() {
    local repo_root="${WORKSPACE_FOLDER:-$PWD}"

    rm -rf "$repo_root/.codex"
    mkdir -pv "$repo_root/.codex"

    if [ -d "$repo_root/.claude/commands" ]; then
        cp -a "$repo_root/.claude/commands" "$repo_root/.codex/"
    fi
}
codex_claude_compat_init

# Add local bin to PATH
export PATH="$HOME/.local/bin:$PATH"
if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q '^export PATH=.*\$HOME/.local/bin' "$HOME/.zshrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    fi
fi

# Persist PERSIST_* env vars to .zshrc
if [ -f "$HOME/.zshrc" ]; then
    env | grep '^PERSIST_' | while IFS='=' read -r key value; do
        real_key="${key#PERSIST_}"
        if ! grep -q "export ${real_key}=" "$HOME/.zshrc"; then
            echo "export ${real_key}='${value}'" >> "$HOME/.zshrc"
        fi
    done
fi

echo "Setup complete!"
