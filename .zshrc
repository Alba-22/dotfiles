# For MacOS, will made any homebrew installed apps available on the path
if [ -d "opt/homebrew/bin/" ]; then
	eval "$(opt/homebrew/bin/brew shellenv)"
fi

# Change cursor style to be a line blinking
echo '\e[5 q'

# Set the directory to store zinit and its plugins
# The first part of this command set to use the XDG_DATA_HOME path, and if it doesn't exists(or it's null),
# then it will use the .local/share path - This is called Parameter Expansion
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Then check for the existence of the zinit.git file. If doesn't exists, then download zinit at the ZINIT_HOME path
if [ ! -d "$ZINIT_HOME" ]; then
	mkdir -p "$(dirname $ZINIT_HOME)"
	git clone git@github.com:zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source the zinit file to start it
source "${ZINIT_HOME}/zinit.zsh"

# Load starship theme
# line 1: `starship` binary as command, from github release
# line 2: starship setup at clone(create init.zsh, completion)
# line 3: pull behavior same as clone, source init.zsh
zinit ice as"command" from"gh-r" \
          atclone"./starship init zsh > init.zsh; ./starship completions zsh > _starship" \
          atpull"%atclone" src"init.zsh"
zinit light starship/starship

# Add zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light agkozak/zsh-z
zinit light Aloxaf/fzf-tab

# Load completions
autoload -U compinit && compinit

# Keybindings
bindkey "^p" history-search-backward
bindkey "^n" history-search-forward

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling:
zstyle ":completion:*" matcher-list "m:{a-z}={A-Za-z}" ## Make completion case insensitive
zstyle ":completion:*" list-colors "${(s.:.)LS_COLORS}"
zstyle ":completion:*" menu no
zstyle ":fzf-tab:complete:cd:*" fzf-preview "ls --color $realpath"

# Other Configs
export LANG=en_US.UTF-8

# Aliases
alias ls="ls -lah --color"
alias cls="clear"
alias cat="batcat"
alias flutter="fvm flutter"
alias c="code"

# Path Exports
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"
## Flutter
export FVM_CACHE_PATH=$HOME/fvm
export PATH=$PATH:$FVM_CACHE_PATH/bin

## For dircolors to work properly on MacOS
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
## Other
export PAGER="less -F"


# Shell integrations
# eval "$(fzf --zsh)" # Waiting for support of version 0.48.1 for Ubuntu

## Homebrew on Linux
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Custom dircolors setup, for the reason that in WSL all folders being listed by ls command that are inside
# of a windows mounted drive, display a blue text with a green background, which is awful to read
eval "$(dircolors -b ~/.config/dircolors)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

PATH=~/.console-ninja/.bin:$PATH

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# claude
export PATH="$HOME/.local/bin:$PATH"

# intellij
export PATH="$HOME/intellij/bin:$PATH"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
