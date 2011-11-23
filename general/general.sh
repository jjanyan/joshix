alias jdestroy='rm -rf '

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
