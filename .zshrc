# ── Completion ────────────────────────────────────────────────
autoload -Uz compinit
compinit

# ── Path ──────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.local/share/pi-node/node-v22.23.2-linux-x64/bin:$PATH"
export SUDO_ASKPASS="$HOME/.local/bin/askpass"

# ── History ───────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
# no AUTO_CD: it grabs bare words before command_not_found_handler can
# zoxide-jump them, and the handler covers its job fuzzily.

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
alias cmt="lgs ~/cmt/commit.lgs"
alias chg="lgs ~/cmt/changelog.lgs"
alias getTheme="bash ~/.local/bin/getTheme"
alias wall="bash ~/.config/myTheme/scripts/wall.sh"
# ── Options ───────────────────────────────────────────────────
# no CORRECT: it prompts on every bare dirname (skills -> kill?) and fights
# the command_not_found_handler jump below.
setopt GLOB_DOTS
setopt NO_BEEP

# ── FZF ───────────────────────────────────────────────────────
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border=rounded"
source /usr/share/fzf/key-bindings.zsh

# ── Plugins ───────────────────────────────────────────────────
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# ── Mise ──────────────────────────────────────────────────────
eval "$(mise activate zsh)"

# ── Zoxide ────────────────────────────────────────────────────
export _ZO_EXCLUDE_DIRS="$HOME"   # never jump to bare $HOME
export _ZO_RESOLVE_SYMLINKS=1     # stow farm: one entry per real dir, not per symlink
eval "$(zoxide init zsh --cmd cd)" # cd itself jumps: `cd skills` just works, plain `cd` still means home

# Bare words jump too: `skills` with no command in $PATH tries the zoxide
# database before giving up. Typos that match nothing fall through to the
# normal "command not found".
# Plumbing note: zsh runs command_not_found_handler in a subshell, so it
# cannot cd directly. It stashes the target in a file; __zoxide_maybe_jump
# (a precmd hook, running in the real shell) consumes it before the next
# prompt. One shell wins if two race; worst case a jump is skipped.
_ZO_JUMP_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/zoxide-jump"
[[ -d "${_ZO_JUMP_FILE:h}" ]] || mkdir -p "${_ZO_JUMP_FILE:h}"
function command_not_found_handler() {
    if (( $# == 1 )); then
        local target
        target="$(zoxide query -- "$1" 2>/dev/null)" && { print -r -- "$target" > "$_ZO_JUMP_FILE"; return 0 }
    fi
    print -u2 "zsh: command not found: $1"
    return 127
}
function __zoxide_maybe_jump() {
    if [[ -f "$_ZO_JUMP_FILE" ]]; then
        local target
        target="$(cat -- "$_ZO_JUMP_FILE")"
        rm -f -- "$_ZO_JUMP_FILE"
        if [[ -n "$target" && -d "$target" && "$target" != "$PWD" ]]; then
            builtin cd -- "$target"
        fi
    fi
}
precmd_functions+=(__zoxide_maybe_jump)

# ── Prompt ────────────────────────────────────────────────────
eval "$(starship init zsh)"
export LIBVA_DRIVER_NAME=iHD
export PATH="$HOME/.cargo/bin:$PATH"
[[ -f ~/azure.sh ]] && source ~/azure.sh
alias snapper="sudo -A snapper"
