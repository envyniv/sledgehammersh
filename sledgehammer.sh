#!/usr/bin/env bash

# References for implementation:
# https://developer.valvesoftware.com/wiki/SteamCMD
# https://gist.github.com/dgibbs64/79a7f3ab3c96a48275c4
# https://github.com/ficool2/HammerPlusPlus-Website/releases
# https://steamdb.info/app/440/depots/
# https://andrealmeid.com/post/2020-05-28-csgo-hammer-linux/#tldr
# https://tf2maps.net/threads/how-to-install-the-hammer-editor-on-linux.42473/

# automatic install-and-execute script for Hammer++

# ERROR CODE DOCUMENTATION:
# - 1 - invalid GAME provided
# - 2 - SteamCMD not installable?
# - 3 - Winetricks not installable?
# - 4 - going to the game bin folder fails
# - 5 - no STEAM_GAMES_FOLDER

function echo_error() {
	local RED='\033[0;31m'
	local NC='\033[0m'
	echo -e "${RED}[ $progname ] $*${NC}" 1>&2
}

function setGame() {
	case $GAME in
		tf2)
			APP=440
			DEPOT=232251
			FOLDER_NAME="Team Fortress 2"
			;;
		csgo)
			APP=730
			DEPOT=732
			FOLDER_NAME="Counter-Strike Global Offensive"
			;;
		*)
			echo_error "Invalid game. Interrupting operation."
			exit 1
			;;
	esac
	_gamepath="$STEAM_GAMES_FOLDER/$FOLDER_NAME"
	export FOLDER_NAME
}

# function edited from https://stackoverflow.com/a/44243842
function getLatestHPP() {
	local installedhppver=$XDG_CONFIG_HOME/hammer/$GAME/.hppver
	# TODO: check for newer version and install
	[ -f "$installedhppver" ] && return
	echo_error Downloading latest Hammer++
	
  local owner=ficool2 project=HammerPlusPlus-Website
  local release_url release_tag
  release_url=$(curl -Ls -o /dev/null -w %'{url_effective}' "https://github.com/$owner/$project/releases/latest")
  release_tag=$(basename "$release_url")
  local tgt_file="hammerplusplus_${GAME}_build${release_tag}"
  wget "https://github.com/$owner/$project/releases/download/$release_tag/$tgt_file.zip" -P "/tmp/"
  unzip "/tmp/$tgt_file.zip" -d "/tmp/"
  mv -f "/tmp/$tgt_file/bin"/* "$_gamepath/bin"
  rm -rf "/tmp/$tgt_file"
  rm "/tmp/$tgt_file.zip"
  ln -s "$_gamepath/bin/hammerplusplus" "$XDG_CONFIG_HOME/hammer/$GAME"
  echo "$release_tag" >"$installedhppver"

	echo_error \
		"Changing necessary settings to have the 'Run Map...' button working properly"

	# WARNING: THIS DOES NOT WORK - HAMMER SPAWNS CONHOST WHICH `cd`s
	#					 INTO COMMANDS PROVIDED, STRIPPING EXECUTABLE NAMES
	#					 WHICH MEANS WE CANNOT USE A NATIVE SOLUTION IN ORDER TO SPAWN THE GAME.
	#					 TO FIX THIS ISSUE, WE SUPERSET CONHOST ENTIRELY, SEEING AS
	# 				 HAMMER++ DOES NOT EVEN NEED CONHOST TO HAVE RUN PROPERLY IN ORDER TO
	#					 CONTINUE EXECUTION.
	#	FIX:		 SEE `hammerd.sh`.
	#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  #dumb replace all instances of '$game_exe' with 'start /unix $game_exe'
  #shellcheck disable=SC2016
  #sed -i -e 's/$game_exe/start \/unix $game_exe/' \
  #	"$XDG_CONFIG_HOME"/hammerplusplus/hammerplusplus_sequences.cfg

  #also add .vmf to all '$file' instances
  perl -pi -e 's/(?<!\s)\$file(?!.bsp)/$file.vmf/' "$SEQUENCESFILE"

  #set expert run mode by default
  sed -i -e 's/ModeExpert=0/ModeExpert=1/' "$SETTINGSFILE"

  # compiled maps in custom folder to avoid contaminating game folders
}

function softlinkAll() {
	echo_error \
		"Soft linking all files from the depot folder over to the game folder."
	cp -rs "${DOWNDEPOT}"/* "$_gamepath/"
}

function yes_or_no {
	while true; do
		printf '%s' "$*"
		read -r -p " [y/n]: " yn
			case $yn in
        [Yy]*) return 0  ;;  
        [Nn]*) echo "Aborted" ; return 1 ;;
     esac
 	done
}

function run_steamcmd {
	# steamcmd is a bitchass motherfucker. he created a new steam folder in my fucking home dir.
	# so i'm making a callout post on twitter dot com

	# worse thing is when used in this fashion it doesn't even output anything.
	steamcmd \
		+login "$(getSteamUser)" "$(getSteamPass)" "$(getSteamGuard)" \
		+download_depot "$APP" "$DEPOT" \
		+quit
}

function hammerplusplus_cmd() {
	WINEPREFIX=$_wineprefix wine cmd /c start hammerplusplus.exe 2>/dev/null
	if [ "$WATCHDOG" = "t" ]; then
		echo_error "Starting Watchdog, please close all other WINE processes"
		echo_error "To avoid killing the wrong things when time comes."
		echo_error
		echo_error "See getConhost() for a worse explanation."
		# No need to start watchdog in the background since
		# wine commands don't hold stdout
		"$SLEDGEHAMMER"/hammerd.sh
	fi
}

function generateDesktopFile() {
	checkInstalled gendesk || getPackage gendesk
	[ -f "$SLEDGEHAMMER/favicon.ico" ] || \
	wget https://raw.githubusercontent.com/ficool2/HammerPlusPlus-Website/main/images/favicon.ico
	gendesk -n --name="$FOLDER_NAME Hammer++" \
		--comment="Hammer++, tuned for $GAME" \
		--terminal=true --path="$SLEDGEHAMMER" \
		--icon=favicon.ico \
		--genericname="VMF Map Editor" \
		--exec="$SLEDGEHAMMER/sledgehammer.sh"
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

SLEDGEHAMMER=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
export DEBUG SLEDGEHAMMER

progname="SledgeHammer.sh"

[ "$DEBUG" ] && set -x

# watchdog is enabled by default except if explicitly disabled
WATCHDOG=${WATCHDOG:-"t"}

STEAMLOC=$XDG_CONFIG_HOME/hammer/.steamlocation

# if no steam games folder (**/common) has been provided, error out.
if [ ! "$STEAM_GAMES_FOLDER" ]; then
	if [ ! -f "$STEAMLOC" ]; then
		echo_error "No STEAM_GAMES_FOLDER provided." && exit 5
	else
		STEAM_GAMES_FOLDER=$(<STEAMLOC)
	fi
fi

echo "$STEAM_GAMES_FOLDER" >"$STEAMLOC"

[ ! "$GAME" ] && GAME="tf2"
setGame

export SETTINGSFILE=$XDG_CONFIG_HOME/hammer/$GAME/hammerplusplus_settings.ini
export SEQUENCESFILE=$XDG_CONFIG_HOME/hammer/$GAME/hammerplusplus_sequences.cfg
export GAMECFGFILE=$XDG_CONFIG_HOME/hammer/$GAME/hammerplusplus_gameconfig.txt

_wineprefix=$HOME/.wine-HammerEditor

# source configuration specific functions
# shellcheck source=/dev/null
. "$XDG_CONFIG_HOME/hammer/hammer.cfg"

#packageManager

# detect first usage - check if wineprefix exists
[ ! -d "$_wineprefix" ] && FIRST_TIME_SETUP=true

# check if steamcmd and winetricks are installed, if not, install them
declare -a a=( steamcmd winetricks wine-mono )
for needed in "${a[@]}"; do
	if ! checkInstalled "$needed"; then
		getPackage "$needed"
	fi
done
unset a

if checkInstalled steamcmd; then
	# Note: A user can only be logged in once at any time (counting both graphical client as well as SteamCMD logins).
	# for ^this^ reason, we are going to close steam.
	if [[ $FIRST_TIME_SETUP = true ]]; then
		if [[ $UNATTENED = true ]]; then
			killall steam
		else
			yes_or_no "Are you fine with killing all steam instances?" && killall steam
		fi
		DOWNDEPOT=$(run_steamcmd | grep -P -o '(?<=Depot download complete : \").+(?=\")')
		# while the path is a unix path, slashes will be mixed; this fixes them.
		DOWNDEPOT="${DOWNDEPOT//\\//}"
	fi
else
	echo_error "SteamCMD missing after supposed installation."
	exit 2
fi

if checkInstalled winetricks; then
	# if used for the first time, install packages in the wine prefix
	if [[ $FIRST_TIME_SETUP = true ]]; then
		WINEARCH=win32 WINEPREFIX=$_wineprefix wine wineboot
		WINEPREFIX=$_wineprefix winetricks \
			dotnet48 vcrun2003 vcrun2005 \
			vcrun2008 vcrun2010 vcrun2012 \
			vcrun2013 vcrun2015
		#dotnet20
	fi
else
	echo_error "Winetricks missing after supposed installation."
	exit 3
fi

[[ $FIRST_TIME_SETUP = true ]] && softlinkAll
getLatestHPP
# executes postInstall if defined (preferrably in hammer.cfg)
[[ $FIRST_TIME_SETUP = true ]] && type postInstall &>/dev/null && postInstall

[[ $FIRST_TIME_SETUP = true ]] && generateDesktopFile
oldpwd=$PWD
#cd shouldn't fail, but if it does, we'll know
cd "$_gamepath/bin" || exit 4
if [[ $FIRST_TIME_SETUP = true ]]; then
	# this starts hammer.exe
	WINEPREFIX=$_wineprefix wine cmd /c start hammer.bat 2>/dev/null
	sleep 3
	pkill -f hammer.exe
fi
hammerplusplus_cmd

cd "$oldpwd" || exit

set +x

# clear exported variables just to be safe
unset DEBUG SLEDGEHAMMER FOLDER_NAME
