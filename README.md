# Sledgehammer.sh

_Hammer++ <3 Linux_

A tiny script for GNU/Linux systems to automatically handle the installation and configuration of
the Hammer++ Map Editor.

Mainly thought for ArchLinux+TF2 users such as myself, but contibutions and additions to make it
work with as many games as possible is appreciated.

## Configuration

To make this script as compatible with as many devices and configurations possible, we require a
`hammer.cfg` file to be present in your `XDG_CONFIG_HOME` directory.

This file should contain the following:

```bash
#!/usr/bin/env bash
# The shebang is present because this is actually 
# a shell script to be sourced by the main script

function getSteamUser() {
	# This function should print out Your
	# Steam account's username.
	echo . . .
}

function getSteamPass() {
	# This function should print out Your
	# Steam account's password.
	echo . . .
}

function getSteamGuard() {
	# This function should print out Your
	# Steam account's Steam Guard code.
	echo . . .
}

function checkInstalled () {
	# This function should merely execute the package manager of choice,
	# Checking for installed packages.
	pacman -Q "$1"
}

function getPackage() {
	# This is a bit more important than the rest.
	# This handles the installation of dependencies needed by the script.
	# Handle this carefully.
}
```
