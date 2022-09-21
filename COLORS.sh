#!/bin/bash
#
# Define some fancy colors, but only if connected to a terminal.
# Thus output to file will be not cluttered anymore
#
#
#
# Use this line in your script to source
# [ -f ${0%%${0##*/}}COLORS.sh ] && source ${0%%${0##*/}}COLORS.sh
#
[ -t 1 ] && {
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    RESET=$(tput setaf 9)
    BOLD=$(tput bold)
    NOATT=$(tput sgr0)
} || {
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""
    RESET=""
    BOLD=""
    NOATT=""
}

TICK="[${GREEN}✓${NOATT}]${GREEN}"
CROSS="[${RED}✗${NOATT}]${RED}"
INFO="[i]${NOATT}"
WARN="[${YELLOW}w${NOATT}]${YELLOW}"
QST="[?]"
IDENT="${NOATT}   "

export MYNAME=${0##*/}

msgok() {
    echo -e "${TICK} ${1}${NOATT}\n"
}

msg() {
    echo -e "${INFO} ${1}${NOATT}"
}
msgwarn() {
    echo -e "${WARN} ${1}${NOATT}"
}
msgfail() {
    echo -e "${CROSS} ${1}${NOATT}"
}
