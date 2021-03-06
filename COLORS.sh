#!/bin/bash
#
# Define some fancy colors, but only if connected to a terminal.
# Thus output to file will be not cluttered anymore
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
    }||{
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

TICK="${NOATT}[${GREEN}✓${NOATT}]${GREEN}"
CROSS="${NOATT}[${RED}✗${NOATT}]${RED}"
INFO="[I]${NOATT}"
WARN="${NOATT}[${YELLOW}W${NOATT}]${YELLOW}"
QST="[?]"
IDENT="${NOATT}   "

MYNAME=$(basename -- $0)


msgok () {
    echo -e "${TICK} {1}${NOATT}\n"
}
msg () {
    echo -e "${IDENT} ${1}${NOATT}"
}
msgwarn () {
    echo -e "${WARN} ${1}${NOATT}"
}
msgfail () {
    echo -e "${CROSS} ${1}${NOATT}"
}
