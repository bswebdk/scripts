#!/bin/bash
#
# Udev Auto Mount script version 1.0 for Debian Wheezy / Jessie and maby other systems
#
# Copyright © 2017 by Torben Bruchhaus
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and associated documentation files (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge, publish, distribute,
# sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
# BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

function show_help() {
cat <<HELP_END
This script is used to create an udev automount rule for a block device. This script
must be run as root (use sudo). The user will be prompted to say Yes or No to the changes
the script will perform. Usage:

  ./uamount.sh block-device [mount-point] [other args]
  
block-device:
  Must be a valid block device which starts with "/dev/", eg "/dev/sda". The defined block
  device must be attached in order to query its UUID.

mount-point:
  If defined it must specify a valid directory name to where the block device will be
  mounted. If the mount point is not an absolute path (eg. /path/to/mount/point) then it
  will be appended to /media" (eg. "usbhdd" becomes "/media/usbhdd". BEWARE: The absolute
  path used as mount point MAY NOT include any blank spaces!
  
  If not defined uamount assumes that you want to perform an un-mount of the specified
  block device. This will eventually remove the entry from fstab, delete the udev rule and
  if user wants it, the mount point will also be removed.

other-args:
  -? | --help          : Show this message.
                        
  -t | --test          : Used to test the script. File "./test.txt" used as fstab directory
                         "./test" used for rule.
                        
  -b | --no-backup     : Do not backup fstab to "fstab_BAK*" where * is an incremental number.
                        
  -r | --no-reload     : Do not reaload udev rules, default when "test" is specified.
  
  -d | --no-delete     : Do not attempt to delete the mounting point. By default the user
                         will be asked if the mounting point should be unmounted (if mounted)
                         and deleted.
                        
  -n | --udev-name     : The name used to create the udev rule, the UUID of the block device
                         will be used if undefinied. The name will always be preceeded by
                         "uamount-", eg. "usbdrive" becomes "uamount-usbdrive".
                        
                         The name used to create an automount must be specified to remove it.
                        
  -p | --udev-priority : Priority for the udev rule, 99 is default.
  
  -y | --yes           : Yes to all questions.
  
  Usage examples:
    
    Automount "/dev/sda" to "/media/MYDRIVE":
      sudo ./uamount.sh /dev/sda MYDRIVE
    
    Remove above automount for "/dev/sda":
      sudo ./uamount.sh /dev/sda
      
    Automount "/dev/sda" to "/media/MYDRIVE" with priority 80 and rule name "mydrive":
      sudo ./uamount.sh /dev/sda MYDRIVE -p 80 -n mydrive
    
    Remove above automount for "/dev/sda" (note that "-p 80 -n mydrive" is required
    here since it is a non default setting):
      sudo ./uamount.sh /dev/sda -p 80 -n mydrive
      
HELP_END
}

function bugout() {
  printf "\e[1m\e[31m$1\n\e[0m"
  exit 1
}

function warning() {
  printf "\e[1m\e[31mWARNING:\e[0m $1\n"
}

# The device to mount, default = /dev/sda
MOUNT_SRC=""

# The point (directory) where to mount the device, no default
MOUNT_DST=""
MAKE_DST=0

# Used to create the name of the udev rule, default priority=99, default name=uamount-DEVICE_UUID
UDEV_PRIO=""
UDEV_NAME=""

# Are we testing the script?
TEST_SCRIPT=0
TEST_FILE="./test.txt"
TEST_DIR="./test/"

# Should be backup the fstab file before modification?
FSTAB_BACKUP=1

# Reload udev
RELOAD_UDEV=1

# Default answers
DEFAULT_ANSWER=2

# Do not delete mount point
NO_DELETE=0

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case $1 in
  
    -\?|--help)
      show_help
      exit
      ;;
    
    -t|--test)
      TEST_SCRIPT=1
      shift
      ;;
      
    -b|--no-backup)
      FSTAB_BACKUP=0
      shift
      ;;
      
    -r|--no-reload)
      RELOAD_UDEV=0
      shift
      ;;
      
    -d|--no-delete)
      NO_DELETE=1
      shift
      ;;
      
    -n|--udev-name)
      UDEV_NAME="$2"
      shift 2
      ;;
    
    -p|--udev-priority)
      UDEV_PRIO="$2"
      shift 2
      ;;
      
    -y|--yes)
      DEFAULT_ANSWER=1
      shift
      ;;
      
    /dev/*)
      MOUNT_SRC=$1
      if [ ! -b "$MOUNT_SRC" ]; then bugout "No such block device: $MOUNT_SRC"; fi
      shift
    ;;
    
    -*)
      bugout "Unknown switch: $1"
      ;;
    
    *)
      if [ -n "$MOUNT_DST" ]; then bugout "Argument not understood: $1"; fi
      MOUNT_DST=$1
      shift
      ;;
    
  esac
done

# Test if we are root
if [ $USER != "root" ]; then bugout "This script must be run as root (sudo it)!"; fi

# Get UUID of the device to mount
DEV_UUID=$(blkid -o value -s UUID "$MOUNT_SRC")
if [ -z "$DEV_UUID" ]; then echo "Unable to get UUID of device \"$MOUNT_SRC\""; exit; fi

# Verify udev priority, if undefined use 99
if [ -z "$UDEV_PRIO" ]; then UDEV_PRIO=99; fi

# Get name of fstab file
FSTAB_FILE=$TEST_FILE
if [ $TEST_SCRIPT -eq 0 ]; then FSTAB_FILE="/etc/fstab"; fi

# Verify udev name, use the device uuid if not defined
if [ -z "$UDEV_NAME" ]; then UDEV_NAME=$DEV_UUID; fi

# Create a name for the udev rule
UDEV_RULE_NAME="$UDEV_PRIO-uamount-$UDEV_NAME.rules"

# Full path for udev file
UDEV_PATH=$TEST_DIR
if [ $TEST_SCRIPT -eq 0 ]; then UDEV_PATH="/lib/udev/rules.d/"; fi
UDEV_FILE="$UDEV_PATH$UDEV_RULE_NAME"

if [ $TEST_SCRIPT -eq 1 ]; then
  echo "MOUNT DEVICE = $MOUNT_SRC"
  echo "DEVICE UUID  = $DEV_UUID"
  echo "MOUNT POINT  = $MOUNT_DST"
  echo "UDEV_PRIO    = $UDEV_PRIO"
  echo "UDEV_NAME    = $UDEV_NAME"
  echo "UDEV RULE    = $UDEV_RULE_NAME"
fi

# Function used to backup the fstab file to fstab_BAK[N]
function backup_fstab() {
  if [ $FSTAB_BACKUP -eq 1 ]; then
    BACKUP_FILE=$FSTAB_FILE"_BAK"
    IDX=1
    while [ -e "$BACKUP_FILE$IDX" ]; do
      let "IDX++"
    done
    cp "$FSTAB_FILE" "$BACKUP_FILE$IDX"
    echo "\"$FSTAB_FILE\" backed up as \"$BACKUP_FILE$IDX\""
  fi
}

function accept_changes() {
  
  # Select message as 1st argument or default
  local MSG="$1"
  if [ "$MSG" == "" ]; then local MSG="Do you want to continue?"; fi
  local MSG="\e[1m\e[34m$MSG [Yes|No] > \e[0m"
  
  # Select default answer
  ANSWER=""
  if [ $DEFAULT_ANSWER -eq 0 ]; then ANSWER="No"
  elif [ $DEFAULT_ANSWER -eq 1 ]; then ANSWER="Yes"
  fi
  
  # Loop until answered correct
  ACCEPTED=2
  while [ $ACCEPTED -eq 2 ]; do
    printf "$MSG"
    if [ -z "$ANSWER" ]; then read -r ANSWER; else echo "$ANSWER"; fi
    ANSWER=${ANSWER,,}
    if [ "$ANSWER" == "yes" ]; then ACCEPTED=1;
    elif [ "$ANSWER" == "no" ]; then
      if [ "$1" == "" ]; then
        # If the answer is not defined by argument, remove MOUNT_DST
        # if created by script and exit
        if [ $MAKE_DST -eq 1 ]; then rm -d "$MOUNT_DST"; fi
        exit
      fi
      ACCEPTED=0
    else
      # Set answer to undefined
      ANSWER=""
    fi
  done
}

if [ -z "$MOUNT_DST" ]; then
  
  # If MOUNT_DST is empty we are removing, get contents of the fstab file
  FSTAB_CUR=$(cat $FSTAB_FILE)
  
  # Get the fstab entry
  FSTAB_ENTRY=$(echo "$FSTAB_CUR" | grep "^UUID=$DEV_UUID")
  if [ -z "$FSTAB_ENTRY" ]; then bugout "No entry for \"$DEV_UUID\" in \"$FSTAB_FILE\""; fi
  
  # Extract the mount point from the entry
  MOUNT_DST=$FSTAB_ENTRY
  # Remove until first blank space
  POS=$(expr index "$MOUNT_DST" " ")
  MOUNT_DST=${MOUNT_DST:POS}
  # Remove after first blank space
  POS=$(expr index "$MOUNT_DST" " ")
  MOUNT_DST=${MOUNT_DST:0:POS-1}
  
  # Remove entry
  FSTAB_NEW=$(echo "$FSTAB_CUR" | sed "/^UUID=$DEV_UUID.*/d")
  
  # If nothing was removed, bug out
  if [ "$FSTAB_CUR" == "$FSTAB_NEW" ]; then bugout "No entry for \"$DEV_UUID\" in \"$FSTAB_FILE\""; fi
  
  # Make sure that the udev rule exists
  if [ ! -e "$UDEV_FILE" ]; then bugout "Udev rule \"$UDEV_FILE\" does not exist"
  else
    TEST=$(cat $UDEV_FILE | grep "ENV{ID_FS_UUID_ENC}==\"$DEV_UUID\"")
    if [ -z "$TEST" ]; then
      echo "Udev rule in \"$UDEV_FILE\" does not match device id \"$DEV_UUID\""
      exit 1
    fi
  fi
  
  # Let user accept the changes
  echo -e "\e[1mYou are about to remove:\e[0m"
  echo -e "  $FSTAB_ENTRY"
  echo -e "\e[1mfrom \"$FSTAB_FILE\" and delete:\e[0m"
  echo -e "  \e[1mFile:\e[0m $UDEV_FILE"
  accept_changes
  
  # Backup fstab
  backup_fstab
  
  # Save the modified fstab
  echo "$FSTAB_NEW" > "$FSTAB_FILE"
  echo "Mount info removed from \"$FSTAB_FILE\""
  
  # Delete the udev rule file
  rm "$UDEV_FILE"
  echo "Udev rule \"$UDEV_FILE\" has been removed"
  
  # Should we remove mount point?
  if [ $NO_DELETE -eq 0 ]; then
    # Ask if the user want to remove the mount point
    accept_changes "Do you want to remove the mount point \"$MOUNT_DST\"? If a device is mounted to it, the device will be unmounted first."
    if [ $ACCEPTED -eq 1 ]; then
      # Do not unmount during script testing
      if [ $TEST_SCRIPT -eq 0 ]; then
        # If mounted then sync and unmount
        if [ -n "$(lsblk "$MOUNT_SRC" 2>&1 | grep "$MOUNT_DST")" ]; then sync && umount "$MOUNT_SRC"; fi
      fi
      # If directory if empty, remove it
      DST_CNT=$(ls -A "$MOUNT_DST")
      if [ -n "$DST_CNT" ]; then warning "\"$MOUNT_DST\" not removed, directory not empty!"
      else
        rm -r "$MOUNT_DST"
        if [ -d "$MOUNT_DST" ]; then warning "Unable to remove \"$MOUNT_DST\""
        else echo "\"$MOUNT_DST\" successfully removed"
        fi
      fi
    fi
  fi
  
else
  
  # If the mount point is not an absolute path, we are prepending /media[/$SUDO_USER]/
  if [[ $MOUNT_DST != *"/"* ]]; then
    if [ -d "/media/$SUDO_USER" ]; then MOUNT_DST="/media/$SUDO_USER/$MOUNT_DST"
    else MOUNT_DST="/media/$MOUNT_DST"
    fi
  fi

  # Make sure that there is not already an entry for the device in fstab
  FSTAB_ENTRY=$(cat $FSTAB_FILE | grep "^UUID=$DEV_UUID")
  if [ -n "$FSTAB_ENTRY" ]; then bugout "An entry for \"$DEV_UUID\" is already present in \"$FSTAB_FILE\""; fi
  
  # Make sure that the udev rule does not already exist
  if [ -e "$UDEV_FILE" ]; then bugout "The udev rule \"$UDEV_FILE\" already exists"; fi
  
  # Make sure that the mount point exist and is empty
  if [ -d "$MOUNT_DST" ]; then
    DST_CNT=$(ls -A "$MOUNT_DST")
    if [ -n "$DST_CNT" ]; then bugout "The mount point \"$MOUNT_DST\" must be empty"; fi
  else
    MAKE_DST=1
    mkdir "$MOUNT_DST"
    if [ -d "$MOUNT_DST" ]; then
      chown $SUDO_UID:$SUDO_GID "$MOUNT_DST"
      chmod 775 "$MOUNT_DST"
    else bugout "Unable to create the mount point"; fi
  fi

  # Get full path of mount point
  MOUNT_DST=$(realpath "$MOUNT_DST")
  
  # Make fstab entry for display
  USER_INFO=""
  if [ -n "$SUDO_UID" ]; then USER_INFO="$USER_INFO,uid=$SUDO_UID"; fi
  if [ -n "$SUDO_GID" ]; then USER_INFO="$USER_INFO,gid=$SUDO_GID"; fi
  FSTAB_ENTRY="UUID=$DEV_UUID $MOUNT_DST auto defaults,noauto$USER_INFO 0 0"
  
  # Let user accept the changes
  echo -e "\e[1mYou are about to append:\e[0m"
  echo -e "  $FSTAB_ENTRY"
  echo -e "\e[1mto \"$FSTAB_FILE\" and create:"
  echo -e "  File:\e[0m $UDEV_FILE"
  if [ $MAKE_DST -eq 1 ]; then echo -e "  \e[1mDirectory:\e[0m $MOUNT_DST"; fi
  accept_changes
  
  # Backup fstab
  backup_fstab
    
  # Add entry to fstab
  echo -e "\n$FSTAB_ENTRY" >> "$FSTAB_FILE"
  echo "Added mount info to \"$FSTAB_FILE\""
  
  # Create the udev rule file
  RULE1="ACTION==\"add\", ENV{ID_FS_UUID_ENC}==\"$DEV_UUID\", RUN+=\"/bin/mount /dev/%k\""
  echo -e "$RULE1\nACTION==\"remove\", ENV{ID_FS_UUID_ENC}==\"$DEV_UUID\", RUN+=\"/bin/umount /dev/%k\"" > "$UDEV_FILE"
  echo "Udev rule \"$UDEV_FILE\" has been created"
  
fi

# Reload udev rules if necessary
if [ $TEST_SCRIPT -eq 1 ]; then RELOAD_UDEV=0; fi
if [ $RELOAD_UDEV -eq 1 ]; then
  echo "Reloading udev rules..."
  udevadm control --reload-rules
else
  echo "Udev rules not reloaded!"
fi

echo -e "\e[1mDone!\e[0m "
