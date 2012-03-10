GREP_OPTIONS="--exclude-dir=\.svn"
export GREP_OPTIONS
export GREP_OPTIONS="-I --color --exclude=\*.svn\*"


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
export PATH=$PATH:~/bin
############################################################################

## add ssh auto complete
complete -W "$(echo `cat ~/.ssh/known_hosts | cut -f 1 -d ' ' | sed -e s/,.*//g | uniq | grep -v "\["`;)" ssh
