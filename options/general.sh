export PATH=/opt/local/bin:/opt/local/sbin:$PATH
export DISPLAY=:0.0
red="\033[1;31m";
norm="\033[0;39m";
cyan="\033[1;36m";
export TERM='xterm-color'
export CLICOLOR='true'
export LSCOLORS="gxfxcxdxbxegedabagacad"
#PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\] \[\033[01;34m\]\w\[\033[01;34m\] \$\[\033[00m\] '
GREEN="\[\033[0;32m\]"
BLUE="\[\033[1;34m\]"
#PS1="\[\033[0;33m\]\u@\h\[\033[00m\]:\n\w\$(parse_git_branch)$\[\033[00m\] "
PS1="\[\033[0;33m\]\u@\h\[\033[00m\]:\n\w$BLUE\$(parse_git_branch)$GREEN $\[\033[00m\] "
