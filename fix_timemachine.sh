#!/bin/bash
set -e

if [ $(id -u) -ne 0 ]; then
	# force this script to run as root
	exec sudo $0 $@
fi

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

echo "Temporarily disabling Time Machine"
tmutil disable

echo "Mounting Time Machine NAS volume"
mkdir -p /Volumes/$VOL
mount_afp $DEST /Volumes/$VOL

echo "Setting permissions"
chflags -R nouchg /Volumes/$VOL/$HOSTNAME.sparsebundle

echo "Attaching time machine sparsebundle"
DISK=$(hdiutil attach -nomount -readwrite -noverify -noautofsck /Volumes/$VOL/$HOSTNAME.sparsebundle | grep HFS | awk '{ print $1 }')
echo "Doing fsck -p. This isn't always necessary, but can help in some troublesome cases"
fsck_hfs -p $DISK
echo "Detaching time machine sparsebundle"
hdiutil detach $DISK

echo "Re-attaching time machine sparsebundle"
DISK=$(hdiutil attach -nomount -readwrite -noverify -noautofsck /Volumes/$VOL/$HOSTNAME.sparsebundle | grep HFS | awk '{ print $1 }')
echo "Doing fsck -drfy. This is what directly addresses the issue."
fsck_hfs -drfy $DISK
echo "Detaching time machine sparsebundle"
hdiutil detach $DISK

echo "Updating plist to remove failed state, so TM will try again"
plutil -remove RecoveryBackupDeclinedDate /Volumes/$VOL/$HOSTNAME.sparsebundle/com.apple.TimeMachine.MachineID.plist
plutil -replace VerificationState -integer 0 /Volumes/$VOL/$HOSTNAME.sparsebundle/com.apple.TimeMachine.MachineID.plist
echo "Unmounting Time Machine NAS volume"
umount /Volumes/$VOL
rm -fd /Volumes/$VOL

echo "Re-enabling Time Machine"
tmutil enable

echo "Starting a backup"
tmutil startbackup
