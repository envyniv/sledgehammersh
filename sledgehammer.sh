#!/usr/bin/env bash

#This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.


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

progname="SledgeHammer.sh"

[ "$DEBUG" ] && set -x

# watchdog is enabled by default except if explicitly disabled
WATCHDOG=${WATCHDOG:-"t"}

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
	# e.g. $HOME/.HammerEditor-tf2; $HOME/.HammerEditor-csgo;
	# _wineprefix=$HOME/.HammerEditor-$GAME
	unset FOLDER_NAME
}

# function edited from https://stackoverflow.com/a/44243842
function getLatestHPP() {
	echo_error Downloading latest Hammer++
	
  local owner=ficool2 project=HammerPlusPlus-Website
  local release_url
  release_url=$(curl -Ls -o /dev/null -w %'{url_effective}' "https://github.com/$owner/$project/releases/latest")
  local release_tag
  release_tag=$(basename "$release_url")
  local tgt_file="hammerplusplus_${GAME}_build${release_tag}"
  wget "https://github.com/$owner/$project/releases/download/$release_tag/$tgt_file.zip" -P "/tmp/"
  unzip "/tmp/$tgt_file.zip" -d "/tmp/"
  mv -f "/tmp/$tgt_file/bin"/* "$_gamepath/bin"
  rm -rf "/tmp/$tgt_file"
  rm "/tmp/$tgt_file.zip"
  ln -s "$_gamepath/bin/hammerplusplus" "$XDG_CONFIG_HOME"

	echo_error \
		"Changing necessary settings to have the 'Run Map...' button working properly"

	# WARNING: THIS DOES NOT WORK - HAMMER SPAWNS CONHOST WHICH `cd`s
	#					 INTO COMMANDS PROVIDED, STRIPPING EXECUTABLE NAMES
	#					 WHICH MEANS WE CANNOT USE A NATIVE SOLUTION IN ORDER TO SPAWN THE GAME.
	#					 TO FIX THIS ISSUE, WE SUPERSET CONHOST ENTIRELY, SEEING AS
	# 				 HAMMER++ DOES NOT EVEN NEED CONHOST TO HAVE RUN PROPERLY IN ORDER TO
	#					 CONTINUE EXECUTION.
	#	FIX:		 SEE FUNCTION `hammerWatchdog`.
	#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  #dumb replace all instances of '$game_exe' with 'start /unix $game_exe'
  #shellcheck disable=SC2016
  #sed -i -e 's/$game_exe/start \/unix $game_exe/' \
  #	"$XDG_CONFIG_HOME"/hammerplusplus/hammerplusplus_sequences.cfg

  #also add .vmf to all '$file' instances
  perl -pi -e 's/(?<!\s)\$file(?!.bsp)/$file.vmf/' \
  	"$XDG_CONFIG_HOME"/hammerplusplus/hammerplusplus_sequences.cfg

  #set expert run mode by default
  sed -i -e 's/ModeExpert=0/ModeExpert=1/' \
  	"$XDG_CONFIG_HOME"/hammerplusplus/hammerplusplus_settings.ini

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

function packageManager() {
	for entry in "${HAMMER_DOWNLOADS[@]}"; do
		if [[ $entry =~ .+\.[0-9]+ ]]; then
			#tf2maps entry
			curl "https://tf2maps.net/downloads/$entry" | grep -P -o '(?<=<div class="bbWrapper">)[\s\S]+(?=<\/div>)'
		else
			echo_error "Link format not recognized for entry \"$entry\". Skipping."
			continue
		fi
	done
	[ "$PKGMANONLY" ] && exit 0
}

function hammerWatchdog() (

	SETTINGSFILE="$XDG_CONFIG_HOME"/hammerplusplus/hammerplusplus_settings.ini
	SEQUENCESFILE="$XDG_CONFIG_HOME"/hammerplusplus/hammerplusplus_sequences.cfg
	# allow process management
	set -m
	
	progname="SledgeHammer Watchdog"

	echo_wd() {
		BLUE='\033[1;34m'
		CLEAR='\033[0m'
		echo -e "${BLUE}[ $progname ] $*${CLEAR}" 1>&2
	}

	getConhost() {
		# This is objectively the wrong way to grab conhost, because this could return literally
		# any instance of conhost, even those not spawned by hammer.

		# However, since wine disconnects from stdout, there is literally nothing i can do to
		# grab the PPID and compare.

		# basically, this is the best we get
		pgrep -x 'conhost\.exe' | tail -n1
	}

	getSequence() {
		echo_wd "Reading last used sequence id."
		seqnum=$(grep -o -P '(?<=LastSequence=)\d+' "$SETTINGSFILE")
		echo_wd "Reading last used sequence from json"
		parseSequence
	}

	fixCommand() {
		# replace arbitrary integers with actual commands
		case $cmd in
			257)
				cmd="cp -f"
				;;
			256)
				cmd="cd"
				;;
			258)
				cmd="rm"
				;;
			259)
				cmd="mv"
				;;
			*)
				winepath -u $cmd 2>/dev/null
				;;
		esac

		
		# replace instances of envvars with actual files
		#parms=${\$game_exe/$parms//$game_exe/}
		#parms=${\$game_exe/$parms//$game_exe/}
		#parms=${\$game_exe/$parms//$game_exe/}

		echo "$cmd $parms"
	}

	parseSequence() {
		declare -a sequence
		#get line number of last sequence
		linenum=$(grep -m "$((seqnum+1))" -n -o '(?<=^\t{1}").+(?=")' "$SEQUENCESFILE" | \
			tail -n1 | cut -d: -f1)
		# we get the text in that sequence, then flatten it
		offset=$((linenum+2))
		values=$( \
			tail -n+"$offset" "$SETTINGSFILE" | \
			head -n$(( \
				$(grep -m1 -n -o -P '^\t\}' "$SETTINGSFILE" | \
				cut -d: -f1) - offset )) | \
			perl -p -e 's/\s+(?=[\"\{\}])//g' \
			)
		entries=$(echo "$values" | grep -P -c '\"\d\"')

		#$bspdir
		#$file
		#$path
		#$bsp_exe
		#$vis_exe
		#$light_exe
	}

	parseEntries() {
		entry=0
		while [ "$entries" -gt "$entry" ]; do
			# https://developer.valvesoftware.com/wiki/Hammer_Run_Map_Expert
			entry_data="$(echo "$entries" | tail -n"$( grep -c '\{')")"
			# check if enabled
			if echo "$entry_data" | grep -P -o '(?<=enable\"\")1(?=\")'; then
				
				# element is enabled, collect data to parse
				cond=$(echo "$entry_data" | grep -P -o '(?<=\"specialcmd\"{2}).+(?=\")')
				if [ "$cond" == "0" ]; then
					# command has specialrun attrib. takes priority over run.
					cmd=$cond
				else
					# command calls to executable
					cmd=$(echo "$entry_data" | grep -P -o '(?<=\"run\"{2}).+(?=\")')
				fi
				parms=$(echo "$entry_data" | \
					grep -P -o '(?<=\"parms\"{2}).+(?=\")' | tail -n1)
				sequence["$entry"]=fixCommand
				
				else
					continue
			fi
			entry=$(( entry + 1 ))
		done
	}

	execSequence () {
		for cmd in "${sequence[@]}"; do
			eval "$cmd"
		done
	}

	process() {
		echo_wd "Started Watchdog"
	
		while true; do
			if getConhost; then
				pid=$(getConhost)
				break
			fi
		done
	
		echo_wd "Found conhost.exe; replacing"
		kill "$pid"
	
		echo_wd "Reading sequence from hammerplusplus cfgs"
		getSequence
	
		parseEntries
	
		execSequence
	}

	process
	
)

function hammerplusplus_cmd() {
	if [ "$WATCHDOG" = "t" ]; then
		set -m
		echo_error "Starting Watchdog, please close all other WINE processes"
		echo_error "To avoid killing the wrong things when time comes."
		echo_error
		echo_error "See getConhost() for a worse explanation."
		hammerWatchdog &
		pid=$!
	fi
	WINEPREFIX=$_wineprefix wine cmd /c start hammerplusplus.exe 2>/dev/null
	if [ "$WATCHDOG" = "t" ]; then
		echo_error Killing Watchdog
		kill "$pid"
		set +m
	fi
	}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# if no steam games folder (**/common) has been provided, error out.
[ ! "$STEAM_GAMES_FOLDER" ] && echo_error "No STEAM_GAMES_FOLDER provided." && exit 5

[ ! "$GAME" ] && GAME="tf2"
setGame

_wineprefix=$HOME/.wine-HammerEditor

# source configuration specific functions
# shellcheck source=/dev/null
. "${XDG_CONFIG_HOME:-$HOME}/hammer.cfg"

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
		# match will be "/home/user/Steamfolder/steamcmd/linux32\steamapps\content\app_appnum\depot_depotnum"
		DOWNDEPOT=$(run_steamcmd | grep -P -o '(?<=Depot download complete : \").+(?=\")')
		# fix all slash bullshittery
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
[[ $FIRST_TIME_SETUP = true ]] && getLatestHPP

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
