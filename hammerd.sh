#!/usr/bin/env bash

# SETTINGSFILE, SEQUENCESFILE and GAMECFGFILE are exported by the main script

[ "$DEBUG" ] && set -x
# allow process management
set -m
set -e

progname=$(basename "$0")

function echo_wd() {
	local BLUE='\033[1;34m'
	local CLEAR='\033[0m'
	echo -e "${BLUE}[ $progname ] $*${CLEAR}" 1>&2
}

function getEditor() {
	pgrep -x 'hammerplusplus.' | tail -n1 >/dev/null
}

function getConhost() {
	# This is objectively the wrong way to grab conhost, because this could return literally
	# any instance of conhost, even those not spawned by hammer.

	# However, since wine disconnects from stdout, there is literally nothing i can do to
	# grab the PPID and compare.

	# basically, this is the best we get
	pgrep -x 'conhost\.exe' | tail -n1
}

function getSequence() {
	echo_wd "Reading last used sequence id."
	seqnum=$(grep -o -P '(?<=LastSequence=)\d+' "$SETTINGSFILE")
	echo_wd "Reading last used sequence from cfg"
	parseSequence
}

function parseCommand() {
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
		\$*)
			true
			#envvars, no need to do operations, we can just overwrite them
			;;
		*)
			# path to file; this we do need to convert
			cmd=$(winepath -u "$cmd" 2>/dev/null)
			;;
	esac
	$cmd $parms
}

function getValueOf() {
	# this expects $buffer to be cut properly
	
	#$1 is the key to get the value of
	echo "$buffer" | grep -P -o "(?<=$1\"{2}).+(?=\")"
}

function getSettingsValue() {
	#$1 is the key to get the value of
	grep -P -o "(?<=$1=).+" "$SETTINGSFILE"

}

function parseSequence() {
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

	#get stuff from gameconfig
	buffer=$(tail -n+"$(grep -c "$FOLDER_NAME" "$GAMECFGFILE" | cut -d: -f1)" \
		"$GAMECFGFILE" | sed 's/\t//g')
	#$bspdir - where to put compiled maps
	bspdir=$(getValueOf BSPDir)
	#$bsp_exe
	bsp_exe=$(getValueOf BSP)
	#$vis_exe
	vis_exe=$(getValueOf Vis)
	#$light_exe
	light_exe=$(getValueOf Light)
	unset buffer
	
	#$file - vmf filename without extension
	file=$(getSettingsValue RecentFile0)
	#$path to map vmf
	path=$(dirname $file)

	parseEntries
}

function getEntry() {
	local entry_line_number
	entry_line_number=$( grep -c "\"$entry\"" | cut -d: -f1)
	echo "$entries" | tail -n+"$entry_line_number" | head -n""
}

function parseEntries() {
	entry=0
	while [ "$entries" -gt "$entry" ]; do
		# https://developer.valvesoftware.com/wiki/Hammer_Run_Map_Expert
		buffer=$(getEntry)
		if [ "$(getValueOf enable)" == 1 ]; then
			# entry is enabled, collect data to parse
			cmd=$(getValueOf specialcmd)
			[ "$cmd" == "0" ] && cmd=$(getValueOf run)
			parms=$(getValueOf parms)
			
			parseCommand
		else
			continue
		fi
		unset buffer
		entry=$(( entry + 1 ))
	done
	[ "$(getSettingsValue WaitForKeypress)" == "1" ] && \
		read -n 1 -s -r -p "Compilation completed. Press any key to resume operation"
	process
}

function end() {
	echo_wd "Editor MIA. Stopping Watchdog..."
	exit
}

function process() {
	echo_wd "Started Watchdog"

	while getEditor; do
		#getConhost && break
		bash_pid=$$
		ps -eo ppid | grep -w $bash_pid
	done
	#getEditor || end

	#echo_wd "Found conhost.exe; replacing"
	#kill "$pid"
	#pkill -f "conhost\.exe"

	#echo_wd "Reading sequence from hammerplusplus cfgs"
	#getSequence
}

sleep 1
process
