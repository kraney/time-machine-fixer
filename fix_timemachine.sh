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
	read -sp "Password for the share: " PASSWD
fi
DEST=afp://${USER}:${PASSWD}@${NAS}/$VOL


###
# Make sure we clean up if we're interrupted
###
function cleanup() {
	if hdiutil info | grep image-path | grep /Volumes/$VOL > /dev/null; then
		info "Cleaning up TM attachment"
		hdiutil detach $DISK
	fi
	if [ -d /Volumes/$VOL ]; then
		info "Cleaning up TM mount"
		umount /Volumes/$VOL
		rm -fd /Volumes/$VOL
	fi
	info "Re-enabling TM"
	tmutil enable
}
trap cleanup SIGHUP SIGINT SIGTERM ERR

###
# Make sure messages are noticeable in to fsck output spam
###
function info() {
	local msg="$1"
	if ! which pv > /dev/null; then
		echo "###################################"
	fi
	echo $msg
	if ! which pv > /dev/null; then
		echo "###################################"
	fi
}

function progress_bar() {
	local funcname="$1"
	local lines="$2"
	local flags="$3"
	if which pv > /dev/null; then
		pv -l "$flags" -N "$funcname" -s "$lines"
	else
		cat
	fi
}

function attach() {
	local bundle=$1
	sync
	DISK=$(hdiutil attach -nomount -readwrite -noverify -noautofsck $bundle | grep HFS | awk '{ print $1 }')
	if [ x"$DISK" == x ]; then
		# Didn't give us a disk name. Must be "temporarily unavailable", i.e.
		# already attached.
		sleep 1
		DISK=$(hdiutil attach -nomount -readwrite -noverify -noautofsck $bundle | grep HFS | awk '{ print $1 }')
	fi
}

info "Temporarily disabling Time Machine"
tmutil disable

info "Mounting Time Machine NAS volume"
mkdir -p /Volumes/$VOL
if ! mount | grep /Volumes/$VOL > /dev/null; then
	mount_afp $DEST /Volumes/$VOL
fi

info "Setting permissions"
chflags -R nouchg /Volumes/$VOL/$HOSTNAME.sparsebundle | progress_bar chflags 1 -t

info "Attaching time machine sparsebundle"
attach /Volumes/$VOL/$HOSTNAME.sparsebundle
info "Doing fsck -p. This isn't always necessary, but can help in some troublesome cases"
fsck_hfs -pfy $DISK 2>&1 | progress_bar "fsck_hfs -p" 40 -tep
info "Detaching time machine sparsebundle"
hdiutil detach $DISK

info "Re-attaching time machine sparsebundle"
attach /Volumes/$VOL/$HOSTNAME.sparsebundle
info "Doing fsck -drfy. This is what directly addresses the issue."
fsck_hfs -drfy $DISK 2>&1 | progress_bar "fsck_hfs -drfy" 40 -tep
info "Detaching time machine sparsebundle"
hdiutil detach $DISK

info "Updating plist to remove failed state, so TM will try again"
plutil -remove RecoveryBackupDeclinedDate /Volumes/$VOL/$HOSTNAME.sparsebundle/com.apple.TimeMachine.MachineID.plist
plutil -replace VerificationState -integer 0 /Volumes/$VOL/$HOSTNAME.sparsebundle/com.apple.TimeMachine.MachineID.plist
info "Unmounting Time Machine NAS volume"
umount /Volumes/$VOL
rm -fd /Volumes/$VOL

info "Re-enabling Time Machine"
tmutil enable

trap - SIGHUP SIGINT SIGTERM

info "Starting a backup"
tmutil startbackup
