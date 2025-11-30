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

# Define target directory (root of destination)
TARGET_DIR="$DEST_DIR"

# Process SSH key from file if path is provided
if [ -n "${SSH_PUBLIC_KEY_PATH:-}" ]; then
    # Expand ~ to user home if present
    SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH/#\~/$HOME}"
    
    # If the path doesn't end with .pub, try appending .pub
    if [[ ! "$SSH_PUBLIC_KEY_PATH" =~ \.pub$ ]]; then
        PUB_KEY_PATH="${SSH_PUBLIC_KEY_PATH}.pub"
        if [ -f "$PUB_KEY_PATH" ]; then
            SSH_PUBLIC_KEY_PATH="$PUB_KEY_PATH"
            echo "Auto-detected public key file: $SSH_PUBLIC_KEY_PATH"
        fi
    fi
    
    if [ ! -f "$SSH_PUBLIC_KEY_PATH" ]; then
        echo "Error: SSH public key file not found: $SSH_PUBLIC_KEY_PATH"
        exit 1
    fi
    
    # Read the entire public key line
    SSH_PUBLIC_KEY_LINE=$(cat "$SSH_PUBLIC_KEY_PATH")
    
    # Validate that it looks like a public key
    if [[ ! "$SSH_PUBLIC_KEY_LINE" =~ ^(ssh-|ecdsa-) ]]; then
        echo "Error: File does not appear to contain a valid SSH public key: $SSH_PUBLIC_KEY_PATH"
        echo "Public keys should start with 'ssh-rsa', 'ssh-ed25519', 'ecdsa-', etc."
        exit 1
    fi
    
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

echo "Generating configuration files in $TARGET_DIR..."

# Copy files
cp -r system-boot/* "$TARGET_DIR/"

# Function to replace placeholder in a file
replace_var() {
    local file="$1"
    local var="$2"
    local value="$3"
    # Use awk to avoid sed escaping issues
    awk -v var="{{$var}}" -v val="$value" '{gsub(var, val); print}' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
}

# Process user-data (cloud-init config)
TARGET_USER_DATA="$TARGET_DIR/user-data"
replace_var "$TARGET_USER_DATA" "USER_NAME" "$USER_NAME"
replace_var "$TARGET_USER_DATA" "DEVICE_HOSTNAME" "$DEVICE_HOSTNAME"
replace_var "$TARGET_USER_DATA" "SSH_PUBLIC_KEY_LINE" "$SSH_PUBLIC_KEY_LINE"
replace_var "$TARGET_USER_DATA" "REPO_URL" "$REPO_URL"
replace_var "$TARGET_USER_DATA" "CLOUDFLARE_TOKEN" "$CLOUDFLARE_TUNNEL_TOKEN"

# Process meta-data
TARGET_META="$TARGET_DIR/meta-data"
awk -v val="$DEVICE_HOSTNAME" '/^local-hostname:/ {$0="local-hostname: " val} {print}' "$TARGET_META" > "$TARGET_META.tmp"
mv "$TARGET_META.tmp" "$TARGET_META"
awk -v val="$DEVICE_HOSTNAME-001" '/^instance-id:/ {$0="instance-id: " val} {print}' "$TARGET_META" > "$TARGET_META.tmp"
mv "$TARGET_META.tmp" "$TARGET_META"

echo "Done! Configuration files are ready in $TARGET_DIR"
