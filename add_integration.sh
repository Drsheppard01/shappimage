#!/bin/sh

# Script to add desktop integration to a partially assembled shImg

# Make sure required tools are present
[ ! $(command -v zip) ]        && echo 'infozip is required to add and use shImg desktop integration!' && cleanExit 1
[ ! $(command -v convert) ]    && echo 'imagemagick (convert) is required to convert icon!'            && cleanExit 1

cleanExit() {
	umount 'mnt'
	rm -r '.APPIMAGE_RESOURCES' '.APPIMAGE_RESOURCES.zip' 'mnt'
	exit "$1"
}

# Allow running as root without squashfuse for Docker/GH actions purposes,
# but don't suggest it because that's stupid
if [ ! $(command -v squashfuse) ] && [ $(id -u) -ne 0 ]; then
	echo 'squashfuse is required to add shImg desktop integration!'
	cleanExit 1
fi

# Give the resources their own directory
tempDir='./.APPIMAGE_RESOURCES'
helpStr="usage: $0 [shImg file] [update info string]

this script is intended for use AFTER building your SquashFS image and
appending it to the appropriate shImg runtime, it will extract desktop
integration info from the SquashFS, integrating it into the zip footer
for easier extraction, along with update information

ONLY USE ON TRUSTED FILES
"

mkdir -p "$tempDir/icon"
mkdir "mnt"

# Add update info
# The begin and end lines are so the update info can be extracted without even
# needing zip installed. THIS IS ONLY TO BE DONE ON THE UPDATE INFORMATION, GPG
# SIG and a possible checksum

# If you have zip, simply extract the file, disregarding the first and final lines

# Here is a one-liner that can extract the update information using `tac` and `sed`:
# tac `file.AppImage` | sed -n '/---END APPIMAGE \[updInfo\]---/,/-----BEGIN APPIMAGE \[updInfo\]-----/{ /-----.*APPIMAGE \[updInfo\]-----/d; p }'
[ "${#2}" -gt 0 ] && echo -ne "---BEGIN APPIMAGE [updInfo]---\n$2\n---END APPIMAGE [updInfo]---"> "$tempDir/updInfo"

offset=$("$1" --appimage-offset)
squashfuse -o offset="$offset" "$1" 'mnt'
[ $? -ne 0 ] && echo 'failed to mount SquashFS!' && cleanExit 1

# Copy first (should be only) desktop entry into what will be our zipped
# desktop integration
cp $(ls --color=never mnt/*.desktop | head -n 1) "$tempDir/desktop_entry"
[ ! -f "$tempDir/desktop_entry" ] && echo 'no desktop entry found!' && cleanExit 1

# Same with icon, should only be one, remove extra if exists (prefer svg)
# Default should be used to set the desktop entry icon, while 256.png should be
# used for thumbnailing
iconName=$(grep 'Icon=' "$tempDir/desktop_entry" | cut -d '=' -f 2-)
cp "mnt/$iconName".png "$tempDir/icon/default.png"
cp "mnt/$iconName".svg "$tempDir/icon/default.svg"
optipng -o 7 -zm 9 -zs 3 "$tempDir/icon/default.png"
[ -f "$tempDir/icon.svg" ] && rm "$tempDir/icon.png"

# Convert icon
iconFile=$(ls "$tempDir/icon/"* | head -n 1 )
size=$(identify "$iconFile" | cut -d ' ' -f 3)
width=$(echo "$size" | cut -d 'x' -f 1)
height=$(echo "$size" | cut -d 'x' -f 2)

# Both generate and check image validity in the same step
convert -resize '256x256' -extent '256x256' -gravity center -background none "$iconFile" "$tempDir/icon/256.png"
[ $? -ne 0 ] && echo 'icon is invalid!' && cleanExit 1
optipng -o 7 -zm 9 -zs 3 "$tempDir/icon/256.png"

cp 'mnt/usr/share/metainfo/'*.appdata.xml "$tempDir/metainfo"

# Do not compress GPG signature or update information as they both should be
# easy to extract as plain text
zip -r -n updInfo '.APPIMAGE_RESOURCES.zip' '.APPIMAGE_RESOURCES'
cat '.APPIMAGE_RESOURCES.zip' >> "$1"
zip -A "$1"

cleanExit 0