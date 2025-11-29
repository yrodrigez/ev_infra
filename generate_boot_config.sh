#!/bin/bash
set -euo pipefail

# Load defaults from .env if present
if [ -f .env ]; then
    source .env
fi

# Check arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <destination_directory>"
    exit 1
fi

DEST_DIR="$1"

# Ensure destination directory exists
if [ ! -d "$DEST_DIR" ]; then
    echo "Error: Destination directory '$DEST_DIR' does not exist."
    exit 1
fi

# Process SSH key from file if path is provided
if [ -n "${SSH_PUBLIC_KEY_PATH:-}" ]; then
    # Expand ~ to user home if present
    SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH/#\~/$HOME}"
    
    if [ ! -f "$SSH_PUBLIC_KEY_PATH" ]; then
        echo "Error: SSH public key file not found: $SSH_PUBLIC_KEY_PATH"
        exit 1
    fi
    
    # Read the entire public key line
    SSH_PUBLIC_KEY_LINE=$(cat "$SSH_PUBLIC_KEY_PATH")
    
    echo "Loaded SSH key from: $SSH_PUBLIC_KEY_PATH"
fi

# Required variables
REQUIRED_VARS=("USER_NAME" "DEVICE_HOSTNAME" "REPO_URL" "CLOUDFLARE_TUNNEL_TOKEN" "SSH_PUBLIC_KEY_LINE")

MISSING_VARS=0
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR:-}" ]; then
        echo "Error: Variable $VAR is not defined."
        MISSING_VARS=1
    fi
done

if [ "$MISSING_VARS" -eq 1 ]; then
    echo "Please define the missing variables in .env or your environment."
    exit 1
fi

# --- Generate Files ---

echo "Generating configuration files in $DEST_DIR..."

# Copy files
cp -r system-boot/* "$DEST_DIR/"

# Function to replace placeholder in a file
replace_var() {
    local file="$1"
    local var="$2"
    local value="$3"
    # Use | as delimiter to avoid issues with slashes in URLs/paths
    sed -i "s|{{$var}}|$value|g" "$file"
}

# Process ssh_authorized_keys.yml
TARGET_SSH="$DEST_DIR/ssh_authorized_keys.yml"
replace_var "$TARGET_SSH" "USER_NAME" "$USER_NAME"
replace_var "$TARGET_SSH" "DEVICE_HOSTNAME" "$DEVICE_HOSTNAME"
replace_var "$TARGET_SSH" "SSH_PUBLIC_KEY_LINE" "$SSH_PUBLIC_KEY_LINE"
replace_var "$TARGET_SSH" "REPO_URL" "$REPO_URL"
replace_var "$TARGET_SSH" "CLOUDFLARE_TOKEN" "$CLOUDFLARE_TUNNEL_TOKEN"

# Process metadata.yml
TARGET_META="$DEST_DIR/metadata.yml"
sed -i "s|local-hostname: .*|local-hostname: $DEVICE_HOSTNAME|" "$TARGET_META"
sed -i "s|instance-id: .*|instance-id: $DEVICE_HOSTNAME-001|" "$TARGET_META"

echo "Done! Configuration files are ready in $DEST_DIR"
