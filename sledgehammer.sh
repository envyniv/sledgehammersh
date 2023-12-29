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
# - 4 - cd'ing around fails
# - 5 - no STEAM_GAMES_FOLDER

function echo_error() {
	local RED='\033[0;31m'
	local NC='\033[0m'
	echo -e "${RED}[ $progname ] $*${NC}" 1>&2
}

function setGame() {
	case ${GAME:=tf2} in
		tf2)
			APP=440
			DEPOT=232251
			FANCYNAME="Team Fortress 2"
			;;
		csgo)
			APP=730
			DEPOT=732
			FANCYNAME="Counter-Strike Global Offensive"
			;;
		*)
			echo_error "Invalid game. Interrupting operation."
			exit 1
			;;
	esac
	_gamepath="$STEAM_GAMES_FOLDER/$FANCYNAME"
	export FANCYNAME
}

function patchHPPSettings() {
	echo_error \
		"Changing necessary settings to have the 'Run Map...' button working properly"

	# WARNING: TRYING TO START THE GAME NATIVELY FROM HAMMER (start /unix $game_exe) 
	#					 DOES NOT WORK - HAMMER SPAWNS CONHOST WHICH `cd`s
	#					 INTO THE PATH OF COMMANDS PROVIDED, STRIPPING EXECUTABLE NAMES
	#					 WHICH MEANS WE CANNOT USE A NATIVE SOLUTION IN ORDER TO SPAWN THE GAME.
	#					 TO FIX THIS ISSUE, WE SUPERSET CONHOST ENTIRELY, SEEING AS
	# 				 HAMMER++ DOES NOT EVEN NEED CONHOST TO HAVE RUN PROPERLY IN ORDER TO
	#					 CONTINUE EXECUTION.
	#	    		 SEE `hammerd.sh` FOR ADDITIONAL DETAILS.

  #also add .vmf to all '$file' instances
  perl -pi -e 's/(?<!\s)\$file(?!.bsp)/$file.vmf/' "$SEQUENCESFILE"

  #set expert run mode by default
  sed -i -e 's/ModeExpert=0/ModeExpert=1/' "$SETTINGSFILE"

  # compiled maps in custom folder to avoid contaminating game folders
}

function downloadHPP() {
	local tgt_file="hammerplusplus_${GAME}_build${release_tag}"
  wget "https://github.com/$owner/$project/releases/download/$release_tag/$tgt_file.zip" -P "/tmp/"
  unzip "/tmp/$tgt_file.zip" -d "/tmp/"
  mv -f "/tmp/$tgt_file/bin"/* "$_gamepath/bin"
  rm -rf "/tmp/$tgt_file"
  rm "/tmp/$tgt_file.zip"
  ln -s "$_gamepath/bin/hammerplusplus" "${XDG_CONFIG_HOME:=$HOME/.config}/hammer/$GAME"
  echo "$release_tag" >"$installedhppver"

	[[ $FIRST_TIME_SETUP = true ]] && patchHPPSettings
}

# function edited from https://stackoverflow.com/a/44243842
function getLatestHPP() {
	local installedhppver=$CONFIGFDL/$GAME/.hppver ver=0
	# TODO: check for newer version and install
	[ -f "$installedhppver" ] && ver=$(<"$installedhppver")

	echo_error Getting latest Hammer++
	
  local owner=ficool2 project=HammerPlusPlus-Website
  local release_url release_tag
  release_url=$(curl -Ls -o /dev/null -w %'{url_effective}' "https://github.com/$owner/$project/releases/latest")
  release_tag=$(basename "$release_url")
  if [[ $release_tag -gt $ver ]]; then
		downloadHPP
  else
  	echo_error "You already have the latest version."
  fi
}

function softlinkAll() {
	echo_error \
		"Soft linking all files from the depot folder over to the game folder."
	cp -rs "${DOWNDEPOT}"/* "$_gamepath/"
	generateDesktopFile
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
	#WINEPREFIX=~/.wine-HammerEditor wineserver -f
	WINEPREFIX=$_wineprefix wine cmd /c start hammerplusplus.exe 2>/dev/null
	#if [ "$WATCHDOG" = "t" ]; then
	#	echo_error "Starting Watchdog, please close all other WINE processes"
	#	echo_error "To avoid killing the wrong things when time comes."
	#	echo_error
	#	echo_error "See getConhost() for a worse explanation."
		# No need to start watchdog in the background since
		# wine commands don't hold stdout
	#	"$SLEDGEHAMMER"/hammerd.sh
	#fi
}

function generateDesktopFile() {
	[ -f "$SLEDGEHAMMER/favicon.ico" ] || \
	wget https://raw.githubusercontent.com/ficool2/HammerPlusPlus-Website/main/images/favicon.ico
	gendesk -n -q --name="Hammer++ ($FANCYNAME)" \
		--comment="Hammer++, tuned for $GAME" \
		--terminal=true --path="$SLEDGEHAMMER" \
		--icon="$SLEDGEHAMMER/favicon.ico" \
		--genericname="VMF Map Editor" \
		--exec="bash -c \"GAME=$GAME $SLEDGEHAMMER/$progname\""
	mv PKGBUILD.desktop "$HOME/.local/share/applications/hammer-$GAME.desktop"
}

function installDepot() {
	# Note: A user can only be logged in once at any time (counting both graphical client as well as SteamCMD logins).
	# for ^this^ reason, we are going to close steam.
	if [[ $UNATTENED = true ]]; then
		killall steam
	else
		yes_or_no "Are you fine with killing all steam instances?" && killall steam
	fi
	DOWNDEPOT=$(run_steamcmd | grep -P -o '(?<=Depot download complete : \").+(?=\")')
	# while the path is a unix path, slashes will be mixed; this fixes them.
	DOWNDEPOT="${DOWNDEPOT//\\//}"
	softlinkAll
}

function makePrefix() {
	# install packages in the wine prefix
	WINEARCH=win32 WINEPREFIX=$_wineprefix wine wineboot
	WINEPREFIX=$_wineprefix winetricks \
		dotnet48 vcrun2003 vcrun2005 \
		vcrun2008 vcrun2010 vcrun2012 \
		vcrun2013 vcrun2015
	#dotnet20 is broken and unneeded
}

function getScriptDeps() {
	# check if steamcmd and winetricks are installed, if not, install them
	declare -a a=( steamcmd winetricks wine-mono gendesk )
	for needed in "${a[@]}"; do
		if ! checkInstalled "$needed"; then
			getPackage "$needed"
		fi
	done
	unset a
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

CONFIGFDL=${XDG_CONFIG_HOME:=$HOME/.config}/hammer

# source configuration specific functions
# (i am forced to use /dev/null because my editor acts weird with shellcheck)
# shellcheck source=/dev/null
. "$CONFIGFDL/hammer.cfg"
setGame

SLEDGEHAMMER=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
cd "$SLEDGEHAMMER" || exit 4

export DEBUG SLEDGEHAMMER

progname=$(basename "$0")

[ "$DEBUG" ] && set -x

# watchdog is enabled by default except if explicitly disabled
WATCHDOG=${WATCHDOG:-"t"}

# if no steam games folder (**/common) has been provided, error out.
[ ! "$STEAM_GAMES_FOLDER" ] && \
	echo_error "No STEAM_GAMES_FOLDER provided." && exit 5


export SETTINGSFILE=$CONFIGFDL/$GAME/hammerplusplus_settings.ini
export SEQUENCESFILE=$CONFIGFDL/$GAME/hammerplusplus_sequences.cfg
export GAMECFGFILE=$CONFIGFDL/$GAME/hammerplusplus_gameconfig.txt

_wineprefix=$HOME/.wine-HammerEditor

getScriptDeps

[ ! -d "$_wineprefix" ] && makePrefix

[[ $FIRST_TIME_SETUP = true ]] && installDepot

getLatestHPP
# executes postInstall if defined (preferrably in hammer.cfg)
[[ $FIRST_TIME_SETUP = true ]] && type postInstall &>/dev/null && postInstall

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
unset DEBUG SLEDGEHAMMER FANCYNAME
