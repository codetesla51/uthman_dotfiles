# ── Completion ────────────────────────────────────────────────
autoload -Uz compinit
compinit

# ── Path ──────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# ── History ───────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt AUTO_CD

# ── Aliases ───────────────────────────────────────────────────
alias ls='lsd'
alias ll='lsd -l'
alias la='lsd -la'
alias lt='lsd --tree'
alias l='lsd -lA'

# dev
alias g='git'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'

# go
alias gor='go run .'
alias gob='go build .'
alias got='go test ./...'
alias gomod='go mod tidy'

# system
alias reload='source ~/.zshrc'
alias zshrc='$EDITOR ~/.zshrc'
alias myip='curl -s ifconfig.me'
alias ports='ss -tulnp'
alias df='df -h'
alias du='du -sh'

# ── Options ───────────────────────────────────────────────────
setopt CORRECT
setopt GLOB_DOTS
setopt NO_BEEP

# ── FZF ───────────────────────────────────────────────────────
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border=rounded"
source /usr/share/fzf/key-bindings.zsh

# ── Plugins ───────────────────────────────────────────────────
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# ── Mise ──────────────────────────────────────────────────────
eval "$(mise activate zsh)"

# ── Zoxide ────────────────────────────────────────────────────
eval "$(zoxide init zsh)"

# ── Prompt ────────────────────────────────────────────────────
eval "$(starship init zsh)"
export LIBVA_DRIVER_NAME=iHD
