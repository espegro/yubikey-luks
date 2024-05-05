#!/bin/bash

# Default slot number
SLOT=1

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --slot) SLOT="$2"; shift ;; # Assign the next argument as the slot number
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift # Move to the next parameter
done

# Initializes an array to store paths of discovered LUKS devices.
luksDevices=()

# Prompts the user to select a LUKS device when multiple are found.
chooseDevice() {
    echo "Multiple LUKS devices found. Please select one for YubiKey configuration:"
    
    local i=1
    for dev in "${luksDevices[@]}"; do
        echo "$i) $dev"
        ((i++))
    done

    read -p "Enter number (1-${#luksDevices[@]}): " choice
    
    # Converts the user input into an array index.
    local index=$((choice-1))

    # Validates user selection and sets the selected device global variable.
    if [[ $index -ge 0 && $index -lt ${#luksDevices[@]} ]]; then
        SELECTED_DEVICE="${luksDevices[index]}"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
}

# Scans all devices listed under /dev/disk/by-id/ for LUKS encryption.
for device in /dev/disk/by-id/*; do
    echo "Checking $device for LUKS..."

    if sudo cryptsetup isLuks "$device" >/dev/null 2>&1; then
        echo "$device is a LUKS device"
        
        # Resolves the real path of the device for consistency in naming.
        realDevice=$(realpath "$device")
        
        # Adds the resolved device path to the array.
        luksDevices+=("$realDevice")
    fi
done

# Filters out duplicate device entries by utilizing an associative array.
declare -A uniqueLuksDevices
for dev in "${luksDevices[@]}"; do
    uniqueLuksDevices["$dev"]=1
done
# Updates luksDevices to only have unique device paths.
luksDevices=("${!uniqueLuksDevices[@]}")

# Handles different scenarios based on the count of unique devices.
if [ ${#luksDevices[@]} -eq 0 ]; then
    echo "No LUKS devices found."
    exit 1
elif [ ${#luksDevices[@]} -eq 1 ]; then
    # Automatically selects the device if it's the only one found.
    SELECTED_DEVICE="${luksDevices[0]}"
    echo "Automatically selected the only LUKS device found: $SELECTED_DEVICE"
else
    # Initiates user selection for multiple devices.
    chooseDevice
fi

# Executes YubiKey configuration if a device is selected.
if [[ -n $SELECTED_DEVICE ]]; then
    echo "Selected LUKS device for YubiKey configuration: $SELECTED_DEVICE"
    
    # Enrolls the YubiKey with the selected LUKS device.
    sudo yubikey-luks-enroll -d "$SELECTED_DEVICE" -s "$SLOT"
    
    # Prepares the ykluks-keyscript in the system.
    sudo mkdir -p /usr/share/yubikey-luks
    sudo cp ykluks-keyscript /usr/share/yubikey-luks
    sudo chmod +x /usr/share/yubikey-luks/ykluks-keyscript
    
    # Defines the path to the crypttab file for modification.
    CRYPTTAB="/etc/crypttab"
    
    # Prepares a temporary file and ensures cleanup upon exit.
    TMPFILE=$(mktemp)
    trap "rm -f $TMPFILE" EXIT
    
    # Retrieves UUID of the selected device for crypttab modification.
    UUID=$(sudo blkid -o value -s UUID "$SELECTED_DEVICE")

        if [[ -z "$UUID" ]]; then
        echo "Unable to find UUID for $SELECTED_DEVICE"
        exit 1
    fi

    # Updates /etc/crypttab with the YubiKey script using the device's UUID.
    awk -v uuid="$UUID" '{
        if ($2 == "UUID="uuid && $4 ~ /^luks/ && $4 !~ /keyscript=\/usr\/share\/yubikey-luks\/ykluks-keyscript/) {
            print $1, $2, $3, $4",discard,keyscript=/usr/share/yubikey-luks/ykluks-keyscript"
        } else {
            print $0
        }
    }' "$CRYPTTAB" > "$TMPFILE"
    
    # Replaces the original crypttab file with the modified version.
    sudo mv "$TMPFILE" "$CRYPTTAB"

    echo "Updated /etc/crypttab successfully."
    
    # Updates the initial RAM filesystem with the changes.
    sudo update-initramfs -u
fi
