#!/bin/bash
set -e

if [ $(id -u) -ne 0 ]; then
	# force this script to run as root
	exec sudo $0 $@
fi

###
# Initialize parameters for the repair operation
###
HOSTNAME=$(hostname -s)

DEST=$(tmutil destinationinfo -X | plutil -extract Destinations.0.URL xml1 - -o - | plutil -p -  | sed 's/\"//g')
USER=$(echo $DEST | cut -d@ -f1 | cut -d/ -f3)
NAS=$(echo $DEST | cut -d@ -f2 | cut -d/ -f1)
VOL=$(echo $DEST | cut -d@ -f2 | cut -d/ -f2)
PASSWD=$(security find-generic-password -w $NAS -a $USER /Library/Keychains/System.keychain)

if [ x$PASSWD == x"" ]; then
	echo -n "share password: "
	stty_orig=$(stty -g)
	stty -echo
	read PASSWD
	stty $stty_orig
	echo
fi
DEST=afp://${USER}:${PASSWD}@${NAS}/$VOL


###
# Make sure we clean up if we're interrupted
###
function cleanup() {
	if hdiutil info | grep image-path | grep /Volumes/$VOL > /dev/null; then
		progress "Cleaning up TM attachment"
		hdiutil detach $DISK
	fi
	if [ -d /Volumes/$VOL ]; then
		progress "Cleaning up TM mount"
		umount /Volumes/$VOL
		rm -fd /Volumes/$VOL
	fi
	progress "Re-enabling TM"
	tmutil enable
}
trap cleanup SIGHUP SIGINT SIGTERM

###
# Make sure messages are noticeable in to fsck output spam
###
function progress() {
	local msg="$1"
	echo "###################################"
	echo $msg
	echo "###################################"
}

progress "Temporarily disabling Time Machine"
tmutil disable

progress "Mounting Time Machine NAS volume"
mkdir -p /Volumes/$VOL
if ! mount | grep /Volumes/$VOL; then
	mount_afp $DEST /Volumes/$VOL
fi

progress "Setting permissions"
chflags -R nouchg /Volumes/$VOL/$HOSTNAME.sparsebundle

progress "Attaching time machine sparsebundle"
DISK=$(hdiutil attach -nomount -readwrite -noverify -noautofsck /Volumes/$VOL/$HOSTNAME.sparsebundle | grep HFS | awk '{ print $1 }')
progress "Doing fsck -p. This isn't always necessary, but can help in some troublesome cases"
fsck_hfs -p $DISK
progress "Detaching time machine sparsebundle"
hdiutil detach $DISK

progress "Re-attaching time machine sparsebundle"
DISK=$(hdiutil attach -nomount -readwrite -noverify -noautofsck /Volumes/$VOL/$HOSTNAME.sparsebundle | grep HFS | awk '{ print $1 }')
progress "Doing fsck -drfy. This is what directly addresses the issue."
fsck_hfs -drfy $DISK
progress "Detaching time machine sparsebundle"
hdiutil detach $DISK

progress "Updating plist to remove failed state, so TM will try again"
plutil -remove RecoveryBackupDeclinedDate /Volumes/$VOL/$HOSTNAME.sparsebundle/com.apple.TimeMachine.MachineID.plist
plutil -replace VerificationState -integer 0 /Volumes/$VOL/$HOSTNAME.sparsebundle/com.apple.TimeMachine.MachineID.plist
progress "Unmounting Time Machine NAS volume"
umount /Volumes/$VOL
rm -fd /Volumes/$VOL

progress "Re-enabling Time Machine"
tmutil enable

trap - SIGHUP SIGINT SIGTERM

progress "Starting a backup"
tmutil startbackup
