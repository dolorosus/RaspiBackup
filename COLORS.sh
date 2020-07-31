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
	
	TICK="[${GREEN}✓${NOATT}]"
	CROSS="[${RED}✗${NOATT}]"
	INFO="[i]"
	QST="[?]"
	
	MYNAME=$(basename -- $0)