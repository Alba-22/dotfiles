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
alias glg="git log -10 --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
alias fetchall="git branch -r | grep -v '\->' | sed \"s,\x1B\[[0-9;]*[a-zA-Z],,g\" | while read remote; do git branch --track \"${remote#origin/}\" \"$remote\"; done"
#alias clear-flutter-projects="sh /Users/alba/dev/bioma/flutter-clean-recursivo.sh"

# Path Exports
## Flutter
#export FLUTTER_HOME=/Users/alba/fvm/default
#export JAVA_HOME=$(/usr/libexec/java_home)
#export ANDROID_HOME=/Users/$USER/Library/Android/sdk
#export FVM_HOME=/Users/alba/fvm
#export PATH=$PATH:$FLUTTER_HOME/bin
#export PATH=$PATH:$FLUTTER_HOME/bin/cache/dart-sdk/bin
#export PATH=$PATH:$HOME/.pub-cache/bin
#export PATH=$PATH:$FVM_HOME/
## Homebew
#export PATH=$PATH:/opt/homebrew/bin
## Android
#export PATH=$PATH:$ANDROID_HOME/tools/bin
#export PATH=$PATH:$ANDROID_HOME/platform-tools
## Other
export PAGER="less -F"


# Shell integrations
# eval "$(fzf --zsh)" # Waiting for support of version 0.48.1 for Ubuntu

## Homebrew on Linux
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Custom dircolors setup, for the reason that in WSL all folders being listed by ls command that are inside
# of a windows mounted drive, display a blue text with a green background, wich is awful to read
eval "$(dircolors -b ~/.config/dircolors)"
