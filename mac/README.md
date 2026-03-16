# macOS Setup

One-line command to set up a fresh Mac with a complete development environment.

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/mac/setup-mac.sh)
```

## What It Installs

The script is interactive — you choose which components to install:

**CLI Tools**: coreutils, git, vim, htop, btop, tree, ffmpeg, and more

**Dev Environment**: Zsh + Oh My Zsh + Powerlevel10k, UV (Python 3.12), NVM (Node.js 22 + pnpm + bun), Docker Desktop, Claude Code CLI

**GUI Apps**: iTerm2, VS Code, Sublime Text, DBeaver, Chrome, Alfred, Obsidian, Ghostty

**Config**: Dotfiles symlinks (.zshrc, .gitconfig), Git setup, SSH key generation, Tailscale VPN

## Features

- **Resumable** — if interrupted, re-run the script and choose to resume from where it left off
- **Idempotent** — safely re-run without reinstalling existing components
- **All inputs upfront** — prompts for everything first, then runs unattended

## Post-Install

After the script completes, check `~/after_setup_todo.txt` for next steps (e.g., open Docker Desktop, authenticate Claude Code, add SSH key to GitHub).
