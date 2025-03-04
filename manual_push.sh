#!/bin/bash

# This script manually pushes your ZSH settings to the GitHub Gist
# Run this if the automatic push in the install script failed

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define the Gist directory
GIST_DIR="$HOME/zsh-settings"

# Check if the Gist directory exists
if [ ! -d "$GIST_DIR" ]; then
    echo "Error: Gist directory not found at $GIST_DIR"
    echo "Please run the install script first."
    exit 1
fi

# Check if it's a git repository
if [ ! -d "$GIST_DIR/.git" ]; then
    echo "Error: $GIST_DIR is not a git repository."
    echo "Please run the install script first."
    exit 1
fi

# Define ZSH configuration files to sync
ZSH_FILES=(
    ".zshrc:zshrc"
    ".zshenv:zshenv"
    ".zprofile:zprofile"
    ".zsh_aliases:zsh_aliases"
    ".zsh_functions:zsh_functions"
)

# Copy local ZSH files to the Gist directory
echo "Copying local ZSH configuration files to Gist directory..."
files_copied=false

for file_pair in "${ZSH_FILES[@]}"; do
    local_file="${HOME}/${file_pair%%:*}"
    gist_file="${GIST_DIR}/${file_pair#*:}"

    if [ -f "$local_file" ]; then
        echo "Found local file: $local_file"
        cp "$local_file" "$gist_file"
        echo "Copied to: $gist_file"
        files_copied=true
    else
        echo "Local file not found: $local_file (skipping)"
        # Create an empty file in the Gist directory if it doesn't exist
        if [ ! -f "$gist_file" ]; then
            touch "$gist_file"
            echo "Created empty file: $gist_file"
        fi
    fi
done

# Check if any files were actually copied
if [ "$files_copied" = false ]; then
    echo "Warning: No local ZSH configuration files were found to copy."
    echo "The following paths were checked:"
    for file_pair in "${ZSH_FILES[@]}"; do
        echo "  ${HOME}/${file_pair%%:*}"
    done

    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
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

# Show the current status
echo "Current Git status:"
(cd "$GIST_DIR" && git status)

# Check if there are any changes to commit
if [ -n "$(cd "$GIST_DIR" && git status --porcelain)" ]; then
    # Commit and push the changes to GitHub
    echo "Committing and pushing configuration to GitHub..."

    (cd "$GIST_DIR" && \
     git add . && \
     git commit -m "ZSH configuration sync at $(date)" && \
     git push -v)

    push_result=$?
    if [ $push_result -ne 0 ]; then
        echo "Warning: Failed to push configuration to GitHub."
        echo "This might be due to authentication issues."
        echo ""
        echo "Try the following steps:"
        echo "1. Make sure you have proper Git credentials set up for GitHub."
        echo "2. If you're using HTTPS, you might need to set up a personal access token."
        echo "3. Try pushing manually with:"
        echo "   cd ~/zsh-settings && git push"
    else
        echo "Successfully pushed configuration to GitHub."
    fi
else
    echo "No changes to commit. Your configuration is already up to date."
fi