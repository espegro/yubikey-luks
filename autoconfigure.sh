#!/bin/bash

# Initialize an array to hold the names of the LUKS devices
luksDevices=()

# Function to enlist devices and capture user choice
chooseDevice() {
    echo "Multiple LUKS devices found. Please select one for YubiKey configuration:"
    local i=1
    for dev in "${luksDevices[@]}"; do
        echo "$i) $dev"
        ((i++))
    done

    read -p "Enter number (1-${#luksDevices[@]}): " choice
    # Adjusting choice to array index
    local index=$((choice-1))

    # Validate user selection
    if [[ $index -ge 0 && $index -lt ${#luksDevices[@]} ]]; then
        # Setting global variable for selected device
        SELECTED_DEVICE="${luksDevices[index]}"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
}

# Loop through all block devices
for device in /dev/disk/by-id/*; do
    echo "Checking $device for LUKS..."

    # Check if the device is a LUKS encrypted
    if sudo cryptsetup isLuks "$device" >/dev/null 2>&1; then
        echo "$device is a LUKS device"
        
        # Resolve the real path of the device to ensure uniformity in the device name format
        realDevice=$(realpath "$device")
        
        # Add the real device path to the list
        luksDevices+=("$realDevice")
    fi
done

# Main logic to handle multiple or single LUKS device scenarios
# Deduplicate luksDevices to ensure each physical device is listed only once
declare -A uniqueLuksDevices
for dev in "${luksDevices[@]}"; do
    uniqueLuksDevices["$dev"]=1
done
luksDevices=("${!uniqueLuksDevices[@]}") # Re-assign unique device paths back to luksDevices

# Check the number of unique devices after deduplication
if [ ${#luksDevices[@]} -eq 0 ]; then
    echo "No LUKS devices found."
    exit 1
elif [ ${#luksDevices[@]} -eq 1 ]; then
    # If there's only one device after deduplication, automatically select it
    SELECTED_DEVICE="${luksDevices[0]}"
    echo "Automatically selected the only LUKS device found: $SELECTED_DEVICE"
else
    # If there are multiple unique devices, prompt the user to choose one
    chooseDevice
fi

if [[ -n $SELECTED_DEVICE ]]; then
    echo "Selected LUKS device for YubiKey configuration: $SELECTED_DEVICE"
    # Now, you can use "$SELECTED_DEVICE" with the yubikey-luks-enroll command
    sudo yubikey-luks-enroll -d "$SELECTED_DEVICE" -s 1
    sudo mkdir -p /usr/share/yubikey-luks
    sudo cp ykluks-keyscript /usr/share/yubikey-luks
    sudo chmod +x /usr/share/yubikey-luks/ykluks-keyscript
    # Path to the crypttab file
    CRYPTTAB="/etc/crypttab"

    # Make sure we have the temporary file removed in case the script fails
    TMPFILE=$(mktemp)
    trap "rm -f $TMPFILE" EXIT

    # Obtain the UUID of the selected LUKS device
    UUID=$(sudo blkid -o value -s UUID "$SELECTED_DEVICE")

    if [[ -z "$UUID" ]]; then
        echo "Unable to find UUID for $SELECTED_DEVICE"
        exit 1
    fi

    # Update the awk command to match the line by UUID
    awk -v uuid="$UUID" '{
        if ($2 == "UUID="uuid && $4 ~ /^luks/ && $4 !~ /keyscript=\/usr\/share\/yubikey-luks\/ykluks-keyscript/) {
            print $1, $2, $3, $4",discard,keyscript=/usr/share/yubikey-luks/ykluks-keyscript"
        } else {
            print $0
        }
    }' "$CRYPTTAB" > "$TMPFILE"

    # Now, move the temporary file to overwrite the original /etc/crypttab, preserving its permissions
    # Requires root permissions
    sudo mv "$TMPFILE" "$CRYPTTAB"

    echo "Updated /etc/crypttab successfully."
    sudo update-initramfs -u
fi