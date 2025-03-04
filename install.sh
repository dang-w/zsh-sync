#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to display usage information
usage() {
    echo "Usage: $0 <gist_url>"
    echo "Example: $0 https://gist.github.com/yourusername/abcd1234efgh5678ijkl"
    echo ""
    echo "Important: Before running this script, you must manually create a GitHub Gist"
    echo "with your ZSH configuration files (zshrc, zshenv, zprofile, etc.)."
    exit 1
}

# Check if gist URL is provided
if [ $# -ne 1 ]; then
    usage
fi

GIST_URL="$1"

# Extract gist ID from URL
GIST_ID=$(echo "$GIST_URL" | grep -oE '[^/]+$')

if [ -z "$GIST_ID" ]; then
    echo "Error: Invalid Gist URL. Please provide a valid GitHub Gist URL."
    usage
fi

echo "Setting up ZSH Settings Sync..."
echo "Note: This script assumes you've already created a GitHub Gist with your ZSH configuration files."

# Check if zsh-settings directory already exists
GIST_DIR="$HOME/zsh-settings"
if [ -d "$GIST_DIR" ]; then
    echo "Directory $GIST_DIR already exists."

    # Check if it's a git repository
    if [ -d "$GIST_DIR/.git" ]; then
        echo "Existing git repository found. Updating..."
        (cd "$GIST_DIR" && git pull)

        # Check if the remote URL matches the provided Gist URL
        CURRENT_REMOTE=$(cd "$GIST_DIR" && git remote get-url origin 2>/dev/null)
        if [[ "$CURRENT_REMOTE" != "$GIST_URL"* && "$CURRENT_REMOTE" != "git@gist.github.com:$GIST_ID.git" ]]; then
            echo "Warning: The existing repository has a different remote URL."
            echo "Current: $CURRENT_REMOTE"
            echo "Provided: $GIST_URL"

            read -p "Do you want to update the remote URL? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                (cd "$GIST_DIR" && git remote set-url origin "$GIST_URL")
                echo "Remote URL updated."
            fi
        fi
    else
        echo "Directory exists but is not a git repository."
        read -p "Do you want to delete it and clone the Gist repository? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing existing directory..."
            rm -rf "$GIST_DIR"

            # Clone the gist
            echo "Cloning Gist repository..."
            git clone "$GIST_URL" "$GIST_DIR"

            if [ $? -ne 0 ]; then
                echo "Error: Failed to clone Gist repository. Please check the URL and your Git configuration."
                exit 1
            fi
        else
            echo "Aborting installation. Please manually resolve the directory conflict."
            exit 1
        fi
    fi
else
    # Create zsh-settings directory and clone the gist
    mkdir -p "$GIST_DIR"

    # Clone the gist
    echo "Cloning Gist repository..."
    git clone "$GIST_URL" "$GIST_DIR"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone Gist repository. Please check the URL and your Git configuration."
        exit 1
    fi
fi

# Configure Git in the repository if not already configured
if [ -z "$(cd "$GIST_DIR" && git config user.name)" ]; then
    echo "Setting up Git configuration in the repository..."
    # Try to get global Git config
    GIT_USER_NAME=$(git config --global user.name)
    GIT_USER_EMAIL=$(git config --global user.email)

    if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then
        (cd "$GIST_DIR" && git config user.name "$GIT_USER_NAME")
        (cd "$GIST_DIR" && git config user.email "$GIT_USER_EMAIL")
        echo "Git configuration copied from global settings."
    else
        echo "Warning: Global Git configuration not found."
        echo "Please set up your Git configuration:"
        read -p "Enter your name for Git: " git_name
        read -p "Enter your email for Git: " git_email

        (cd "$GIST_DIR" && git config user.name "$git_name")
        (cd "$GIST_DIR" && git config user.email "$git_email")
        echo "Git configuration set up."
    fi
fi

# Define ZSH configuration files to sync
ZSH_FILES=(
    ".zshrc:zshrc"
    ".zshenv:zshenv"
    ".zprofile:zprofile"
    ".zsh_aliases:zsh_aliases"
    ".zsh_functions:zsh_functions"
)

# Verify that the required files exist in the Gist
echo "Verifying Gist contains the necessary ZSH configuration files..."
missing_files=false

for file_pair in "${ZSH_FILES[@]}"; do
    gist_file="${GIST_DIR}/${file_pair#*:}"

    if [ ! -f "$gist_file" ]; then
        echo "Warning: File not found in Gist: ${file_pair#*:}"
        missing_files=true
    else
        echo "Found file in Gist: ${file_pair#*:}"
    fi
done

if [ "$missing_files" = true ]; then
    echo ""
    echo "Some expected ZSH configuration files are missing from your Gist."
    echo "Please make sure you've created the necessary files in your Gist:"
    echo "- zshrc (required)"
    echo "- zshenv (if you use it)"
    echo "- zprofile (if you use it)"
    echo "- zsh_aliases (if you use it)"
    echo "- zsh_functions (if you use it)"
    echo ""
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting installation."
        exit 1
    fi
fi

# Create symlinks between local ZSH files and Gist files
echo "Creating symlinks for ZSH configuration files..."

for file_pair in "${ZSH_FILES[@]}"; do
    local_file="${HOME}/${file_pair%%:*}"
    gist_file="${GIST_DIR}/${file_pair#*:}"

    # Only create symlinks for files that exist in the Gist
    if [ -f "$gist_file" ]; then
        # Backup existing file if it's not a symlink
        if [ -f "$local_file" ] && [ ! -L "$local_file" ]; then
            echo "Backing up existing file: $local_file → $local_file.backup"
            cp "$local_file" "$local_file.backup"
        fi

        # Remove existing file if it's not a symlink
        if [ -f "$local_file" ] && [ ! -L "$local_file" ]; then
            rm "$local_file"
        fi

        # Create symlink
        ln -sf "$gist_file" "$local_file"
        echo "Created symlink: $local_file → $gist_file"
    fi
done

# Make the script executable
chmod +x "$SCRIPT_DIR/zsh-sync.sh"

# Create the .last_hash file with the current hash to prevent immediate sync prompts
LAST_HASH_FILE="$GIST_DIR/.last_hash"
CURRENT_HASH=$(cd "$GIST_DIR" && git rev-parse HEAD)
echo "$CURRENT_HASH" > "$LAST_HASH_FILE"
echo "Created initial hash file to prevent immediate sync prompts."

# Set up automatic startup based on OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "Setting up LaunchAgent for macOS..."

    # Copy the plist file
    cp "$SCRIPT_DIR/com.user.zshsync.plist" ~/Library/LaunchAgents/

    # Update the path in the plist file
    sed -i '' "s|/path/to/zsh-sync.sh|$SCRIPT_DIR/zsh-sync.sh|g" ~/Library/LaunchAgents/com.user.zshsync.plist

    # Load the LaunchAgent
    launchctl load ~/Library/LaunchAgents/com.user.zshsync.plist

    echo "LaunchAgent installed. ZSH Settings Sync will start automatically on login."
else
    # Linux
    echo "Setting up cron job for Linux..."

    # Check if crontab exists
    crontab -l > /tmp/current_crontab 2>/dev/null || echo "" > /tmp/current_crontab

    # Add our job to crontab if it doesn't exist
    if ! grep -q "zsh-sync.sh" /tmp/current_crontab; then
        echo "*/20 * * * * $SCRIPT_DIR/zsh-sync.sh > /dev/null 2>&1" >> /tmp/current_crontab
        crontab /tmp/current_crontab
        echo "Cron job installed. ZSH Settings Sync will run every 20 minutes."
    else
        echo "Cron job already exists."
    fi

    rm /tmp/current_crontab
fi

# Run the script for initial setup with a special flag to skip checks
echo "Running initial setup..."
"$SCRIPT_DIR/zsh-sync.sh" --skip-initial-checks &

echo "Setup complete! ZSH Settings Sync is now running in the background."
echo "You can check the log file at ~/zsh-settings/sync.log"