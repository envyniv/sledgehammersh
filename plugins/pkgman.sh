#!/usr/bin/env bash

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
