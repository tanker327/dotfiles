#!/bin/bash

#####################################################
# Rebuild Dotfiles Configuration Script
#####################################################
# Usage: bash ~/dotfiles/vps/rebuild-dotfiles.sh
# This script fixes symlinks for zsh, git configs
# and reinstalls Oh My Zsh components if needed
#####################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as regular user (not root)
if [ "$EUID" -eq 0 ]; then
    log_error "This script should NOT be run as root"
    log_error "Run as your regular user: bash ~/dotfiles/vps/rebuild-zsh.sh"
    exit 1
fi

section_header "Rebuilding Dotfiles Configuration"

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/.backup"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if dotfiles directory exists
if [ ! -d "$DOTFILES_DIR" ]; then
    log_error "Dotfiles directory not found at $DOTFILES_DIR"
    log_error "Please clone dotfiles first: git clone https://github.com/tanker327/dotfiles.git ~/dotfiles"
    exit 1
fi

#####################################################
# Git Configuration
#####################################################

section_header "Setting Up Git Configuration"

# Backup and symlink gitconfig
if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then
    log_info "Backing up existing .gitconfig..."
    mv -f "$HOME/.gitconfig" "$BACKUP_DIR/.gitconfig.backup-$(date +%Y%m%d_%H%M%S)"
elif [ -L "$HOME/.gitconfig" ]; then
    log_info "Removing old .gitconfig symlink..."
    rm -f "$HOME/.gitconfig"
fi

log_info "Creating .gitconfig symlink..."
ln -sf "$DOTFILES_DIR/git/gitconfig" "$HOME/.gitconfig"
log_success "Symlinked .gitconfig -> $DOTFILES_DIR/git/gitconfig"

# Backup and symlink gitignore_global
if [ -f "$HOME/.gitignore_global" ] && [ ! -L "$HOME/.gitignore_global" ]; then
    log_info "Backing up existing .gitignore_global..."
    mv -f "$HOME/.gitignore_global" "$BACKUP_DIR/.gitignore_global.backup-$(date +%Y%m%d_%H%M%S)"
elif [ -L "$HOME/.gitignore_global" ]; then
    log_info "Removing old .gitignore_global symlink..."
    rm -f "$HOME/.gitignore_global"
fi

log_info "Creating .gitignore_global symlink..."
ln -sf "$DOTFILES_DIR/git/gitignore_global" "$HOME/.gitignore_global"
log_success "Symlinked .gitignore_global -> $DOTFILES_DIR/git/gitignore_global"

#####################################################
# Zsh Configuration
#####################################################

section_header "Setting Up Zsh Configuration"

# Backup existing .zshrc if it's not a symlink
if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    log_info "Backing up existing .zshrc..."
    mv -f "$HOME/.zshrc" "$BACKUP_DIR/.zshrc.backup-$(date +%Y%m%d_%H%M%S)"
    log_success "Backed up to $BACKUP_DIR"
elif [ -L "$HOME/.zshrc" ]; then
    log_info "Removing old .zshrc symlink..."
    rm -f "$HOME/.zshrc"
fi

# Create zshrc symlink
log_info "Creating .zshrc symlink..."
ln -sf "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
log_success "Symlinked .zshrc -> $DOTFILES_DIR/zsh/zshrc"

# Backup and symlink p10k config
if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
    log_info "Backing up existing .p10k.zsh..."
    mv -f "$HOME/.p10k.zsh" "$BACKUP_DIR/.p10k.zsh.backup-$(date +%Y%m%d_%H%M%S)"
elif [ -L "$HOME/.p10k.zsh" ]; then
    log_info "Removing old .p10k.zsh symlink..."
    rm -f "$HOME/.p10k.zsh"
fi

# Create p10k symlink if file exists in dotfiles
if [ -f "$DOTFILES_DIR/zsh/p10k.zsh" ]; then
    log_info "Creating .p10k.zsh symlink..."
    ln -sf "$DOTFILES_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh"
    log_success "Symlinked .p10k.zsh -> $DOTFILES_DIR/zsh/p10k.zsh"
else
    log_warning "No p10k.zsh found in dotfiles (will be created on first p10k configure)"
fi

# Check and install Oh My Zsh if needed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    section_header "Installing Oh My Zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log_success "Oh My Zsh installed"
else
    log_info "Oh My Zsh already installed"
fi

# Install Powerlevel10k theme
section_header "Installing Powerlevel10k Theme"
P10K_DIR="$ZSH_CUSTOM/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    log_info "Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    log_success "Powerlevel10k theme installed"
else
    log_info "Powerlevel10k already installed"
fi

# Install zsh-autosuggestions
section_header "Installing Zsh Plugins"
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    log_info "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    log_success "zsh-autosuggestions installed"
else
    log_info "zsh-autosuggestions already installed"
fi

# Install zsh-syntax-highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    log_info "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    log_success "zsh-syntax-highlighting installed"
else
    log_info "zsh-syntax-highlighting already installed"
fi

# Verify symlinks
section_header "Verification"
echo ""
log_info "Verifying Git symlinks:"
ls -la "$HOME/.gitconfig" "$HOME/.gitignore_global" 2>/dev/null || true
echo ""
log_info "Verifying Zsh symlinks:"
ls -la "$HOME/.zshrc" "$HOME/.p10k.zsh" 2>/dev/null || true
echo ""

section_header "Complete!"
echo ""
echo -e "${GREEN}✓ Dotfiles configuration rebuilt successfully${NC}"
echo ""
echo -e "${YELLOW}What was configured:${NC}"
echo "  ✓ Git configuration (.gitconfig, .gitignore_global)"
echo "  ✓ Zsh configuration (.zshrc, .p10k.zsh)"
echo "  ✓ Oh My Zsh and plugins"
echo "  ✓ Powerlevel10k theme"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Verify git config: git config --list | grep user"
echo "2. Reload your shell: source ~/.zshrc"
echo "3. Or restart your terminal session"
if [ ! -f "$HOME/.p10k.zsh" ] || [ ! -f "$DOTFILES_DIR/zsh/p10k.zsh" ]; then
    echo "4. Configure Powerlevel10k: p10k configure"
fi
echo ""
echo -e "${BLUE}Backups saved to: $BACKUP_DIR${NC}"
echo ""
