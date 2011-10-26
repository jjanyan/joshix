export PATH=/opt/local/bin:/opt/local/sbin:$PATH
export DISPLAY=:0.0
export TERM='xterm-color'
export CLICOLOR='true'
export LSCOLORS="gxfxcxdxbxegedabagacad"

# {{
#GREEN="\[\033[0;32m\]"
#BLUE="\[\033[1;34m\]"
#RED="\[\033[1;31m\]"
#PS1="\[\033[0;33m\]\u@\h\[\033[00m\]:\n\w$BLUE\$(parse_git_branch)$RED $\[\033[00m\] "
# }}

# {{
Black="$(tput setaf 0)"
BlackBG="$(tput setab 0)"
DarkGrey="$(tput bold ; tput setaf 0)"
LightGrey="$(tput setaf 7)"
LightGreyBG="$(tput setab 7)"
White="$(tput bold ; tput setaf 7)"
Red="$(tput setaf 1)"
RedBG="$(tput setab 1)"
LightRed="$(tput bold ; tput setaf 1)"
Green="$(tput setaf 2)"
GreenBG="$(tput setab 2)"
LightGreen="$(tput bold ; tput setaf 2)"
Brown="$(tput setaf 3)"
BrownBG="$(tput setab 3)"
#Yellow="$(tput bold ; tput setaf 3)"
Yellow="$(tput setaf 3)"
Blue="$(tput setaf 4)"
BlueBG="$(tput setab 4)"
#LightBlue="$(tput bold ; tput setaf 4)"
LightBlue="$(tput setaf 4)"
Purple="$(tput setaf 5)"
PurpleBG="$(tput setab 5)"
Pink="$(tput bold ; tput setaf 5)"
Cyan="$(tput setaf 6)"
CyanBG="$(tput setab 6)"
LightCyan="$(tput bold ; tput setaf 6)"
NC="$(tput sgr0)" # No Color
# }}


PS1="\[$LightBlue\]\u\[$Brown\]@\[$LightBlue\]\h:\[$Yellow\]\n\w\[$Blue\]\$(parse_git_branch)\[$Green\] $\[$NC\] "

CDPATH=".:~:/var/www/html/announcemedia/"

if [ -f /opt/local/etc/bash_completion ]; then
	. /opt/local/etc/bash_completion
fi

