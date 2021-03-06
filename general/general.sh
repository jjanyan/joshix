GREP_OPTIONS="--exclude-dir=\.svn"
#export GREP_OPTIONS
export GREP_OPTIONS="-s -I --color --exclude=\*.svn\*"


############################################################################
## SET BASH COMMAND VARIABLES
############################################################################
set -o vi
bind -m vi-insert "\C-l":clear-screen
export HISTFILESIZE=3000 # the bash history should save 3000 commands
export HISTCONTROL=ignoreboth # don't put duplicate lines in the history. & ignore things that start with a space
############################################################################

############################################################################
## SET PATHS
############################################################################
export PATH=$PATH:~/.bin:~/.bin_local
############################################################################

## add ssh auto complete
complete -W "$(echo `cat ~/.ssh/known_hosts | cut -f 1 -d ' ' | sed -e s/,.*//g | uniq | grep -v "\["`;)" ssh
alias gs='git status'
alias gd="git diff $1"
alias gdw="git diff --word-diff $1"
alias ga="git add -A $1"
alias gc="git commit"
alias gp="git pull"
alias gpr="git pull --rebase"
alias gl="git log --oneline --decorate"
alias gls="git log --pretty=format:'%C(dim white)%h %ad%Creset %C(normal)%s%Creset | %C(yellow)%an%Creset' --stat"
#%C(white)white%Creset
alias gflush='git branch --merged | grep -v "\*" | xargs -n 1 git branch -d'
