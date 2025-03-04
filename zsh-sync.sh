#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configuration
SYNC_INTERVAL=1200  # Check every 20 minutes (1200 seconds)
GIST_DIR="$HOME/zsh-settings"
LOG_FILE="$GIST_DIR/sync.log"
LAST_HASH_FILE="$GIST_DIR/.last_hash"
ZSH_PATHS=()
OS_TYPE=""
SKIP_INITIAL_CHECKS=false

# Check for command line arguments
if [[ "$1" == "--skip-initial-checks" ]]; then
    SKIP_INITIAL_CHECKS=true
fi

# Detect OS and set appropriate paths
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    OS_TYPE="macOS"
    ZSH_PATHS=(
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.zprofile"
        "$HOME/.zsh_aliases"
        "$HOME/.zsh_functions"
    )
    GIST_ZSH_PATHS=(
        "$GIST_DIR/zshrc"
        "$GIST_DIR/zshenv"
        "$GIST_DIR/zprofile"
        "$GIST_DIR/zsh_aliases"
        "$GIST_DIR/zsh_functions"
    )
else
    # Linux/WSL
    OS_TYPE="Linux"
    ZSH_PATHS=(
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.zprofile"
        "$HOME/.zsh_aliases"
        "$HOME/.zsh_functions"
    )
    GIST_ZSH_PATHS=(
        "$GIST_DIR/zshrc"
        "$GIST_DIR/zshenv"
        "$GIST_DIR/zprofile"
        "$GIST_DIR/zsh_aliases"
        "$GIST_DIR/zsh_functions"
    )
fi

# Function to log messages
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo "[$timestamp] $1"
}

# Function to get current git hash
get_current_hash() {
    (cd "$GIST_DIR" && git rev-parse HEAD)
}

# Function to check for local changes
check_local_changes() {
    local has_changes=false

    for i in "${!ZSH_PATHS[@]}"; do
        if [[ -f "${ZSH_PATHS[$i]}" ]]; then
            if ! cmp -s "${ZSH_PATHS[$i]}" "${GIST_ZSH_PATHS[$i]}"; then
                log_message "Changes detected in ${ZSH_PATHS[$i]}"
                has_changes=true
            fi
        fi
    done

    echo "$has_changes"
}

# Function to check for remote changes
check_remote_changes() {
    # Skip check if we're in skip mode (just after installation)
    if [[ "$SKIP_INITIAL_CHECKS" == true ]]; then
        log_message "Skipping remote check - initial run after installation"
        return 1
    fi

    # Skip check if the last hash file was modified less than 5 minutes ago
    if [[ -f "$LAST_HASH_FILE" ]]; then
        local file_mod_time=$(stat -f %m "$LAST_HASH_FILE")
        local current_time=$(date +%s)
        local time_diff=$((current_time - file_mod_time))

        if [[ $time_diff -lt 300 ]]; then  # 5 minutes = 300 seconds
            log_message "Skipping remote check - last check was less than 5 minutes ago"
            return 1
        fi
    fi

    # Fetch the latest changes from remote
    (cd "$GIST_DIR" && git fetch -q)

    # Get the current and remote hashes
    local current_hash=$(get_current_hash)
    local remote_hash=$(cd "$GIST_DIR" && git rev-parse origin/master 2>/dev/null || git rev-parse origin/main 2>/dev/null)

    # If we have a last hash file, read it
    local last_hash=""
    if [[ -f "$LAST_HASH_FILE" ]]; then
        last_hash=$(cat "$LAST_HASH_FILE")
    fi

    # If the remote hash is different from both the current hash and the last hash, changes detected
    if [[ "$current_hash" != "$remote_hash" && "$last_hash" != "$remote_hash" ]]; then
        log_message "Remote hash ($remote_hash) differs from current hash ($current_hash) and last hash ($last_hash)"
        return 0  # Changes detected
    else
        return 1  # No changes
    fi
}

# Function to handle merge conflicts
handle_conflicts() {
    if (cd "$GIST_DIR" && git status | grep -q "both modified"); then
        log_message "Merge conflicts detected!"
        show_notification "ZSH Settings Sync" "Merge conflicts detected. Manual resolution required."

        # Create backup of conflicted files
        mkdir -p "$GIST_DIR/conflicts_backup"
        cp "$GIST_DIR"/*_BACKUP_* "$GIST_DIR/conflicts_backup/" 2>/dev/null

        # Use local version by default
        (cd "$GIST_DIR" && git checkout --ours .)
        (cd "$GIST_DIR" && git add .)
        (cd "$GIST_DIR" && git commit -m "Auto-resolved conflicts by keeping local version")

        log_message "Conflicts auto-resolved by keeping local version. Backups in $GIST_DIR/conflicts_backup/"
    fi
}

# Function to push changes
push_changes() {
    log_message "Pushing changes to remote..."

    # Copy current settings to gist directory
    for i in "${!ZSH_PATHS[@]}"; do
        if [[ -f "${ZSH_PATHS[$i]}" ]]; then
            cp "${ZSH_PATHS[$i]}" "${GIST_ZSH_PATHS[$i]}"
        fi
    done

    # Commit and push changes
    (cd "$GIST_DIR" && \
     git add . && \
     git commit -m "Auto-sync: Updated ZSH settings on $OS_TYPE at $(date)" && \
     git push)

    if [ $? -eq 0 ]; then
        log_message "Successfully pushed changes"
        echo "$(get_current_hash)" > "$LAST_HASH_FILE"
        return 0
    else
        log_message "Failed to push changes"
        return 1
    fi
}

# Function to pull changes
pull_changes() {
    log_message "Pulling changes from remote..."

    (cd "$GIST_DIR" && git pull)
    pull_result=$?

    # Handle any merge conflicts
    handle_conflicts

    if [ $pull_result -eq 0 ]; then
        log_message "Successfully pulled changes"
        echo "$(get_current_hash)" > "$LAST_HASH_FILE"

        # Copy updated files from gist to local zsh config
        for i in "${!GIST_ZSH_PATHS[@]}"; do
            if [[ -f "${GIST_ZSH_PATHS[$i]}" ]]; then
                cp "${GIST_ZSH_PATHS[$i]}" "${ZSH_PATHS[$i]}"
                log_message "Updated ${ZSH_PATHS[$i]}"
            fi
        done

        # Source zshrc to apply changes if zsh is the current shell
        if [[ "$SHELL" == *"zsh"* ]]; then
            log_message "Reloading ZSH configuration..."
            source "$HOME/.zshrc" 2>/dev/null || true
        fi

        return 0
    else
        log_message "Failed to pull changes"
        return 1
    fi
}

# Function to show desktop notification
show_notification() {
    local title="$1"
    local message="$2"

    if [[ "$OS_TYPE" == "macOS" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\""
    else
        # For Linux, try various notification methods
        if command -v notify-send &> /dev/null; then
            notify-send "$title" "$message"
        elif command -v zenity &> /dev/null; then
            zenity --notification --text="$title: $message"
        fi
    fi
}

# Function to prompt user for action
prompt_user() {
    local action="$1"
    local response

    if [[ "$action" == "push" ]]; then
        show_notification "ZSH Settings Sync" "Local changes detected. Sync to GitHub?"

        # Use AppleScript dialog on macOS, zenity on Linux
        if [[ "$OS_TYPE" == "macOS" ]]; then
            response=$(osascript -e 'display dialog "Local ZSH settings have changed. Push to GitHub?" buttons {"Cancel", "Push"} default button "Push"' -e 'set response to button returned of result' 2>/dev/null || echo "Cancel")

            if [[ "$response" == "Push" ]]; then
                push_changes
            else
                log_message "User declined to push changes"
            fi
        else
            # For Linux
            if command -v zenity &> /dev/null; then
                zenity --question --text="Local ZSH settings have changed. Push to GitHub?" --title="ZSH Settings Sync" 2>/dev/null
                if [ $? -eq 0 ]; then
                    push_changes
                else
                    log_message "User declined to push changes"
                fi
            else
                # Fallback to terminal prompt
                read -p "Local ZSH settings have changed. Push to GitHub? (y/n) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    push_changes
                else
                    log_message "User declined to push changes"
                fi
            fi
        fi
    elif [[ "$action" == "pull" ]]; then
        show_notification "ZSH Settings Sync" "Remote changes detected. Update local settings?"

        if [[ "$OS_TYPE" == "macOS" ]]; then
            response=$(osascript -e 'display dialog "Remote ZSH settings have changed. Pull from GitHub?" buttons {"Cancel", "Pull"} default button "Pull"' -e 'set response to button returned of result' 2>/dev/null || echo "Cancel")

            if [[ "$response" == "Pull" ]]; then
                pull_changes
            else
                log_message "User declined to pull changes"
            fi
        else
            # For Linux
            if command -v zenity &> /dev/null; then
                zenity --question --text="Remote ZSH settings have changed. Pull from GitHub?" --title="ZSH Settings Sync" 2>/dev/null
                if [ $? -eq 0 ]; then
                    pull_changes
                else
                    log_message "User declined to pull changes"
                fi
            else
                # Fallback to terminal prompt
                read -p "Remote ZSH settings have changed. Pull from GitHub? (y/n) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    pull_changes
                else
                    log_message "User declined to pull changes"
                fi
            fi
        fi
    fi
}

# Function to create symlinks
create_symlinks() {
    log_message "Setting up symlinks..."

    for i in "${!ZSH_PATHS[@]}"; do
        # Create backup if file exists
        if [[ -f "${ZSH_PATHS[$i]}" && ! -L "${ZSH_PATHS[$i]}" ]]; then
            log_message "Creating backup of ${ZSH_PATHS[$i]}"
            cp "${ZSH_PATHS[$i]}" "${ZSH_PATHS[$i]}.backup"

            # Copy to gist directory
            cp "${ZSH_PATHS[$i]}" "${GIST_ZSH_PATHS[$i]}"
        fi

        # Create symlink
        if [[ -f "${GIST_ZSH_PATHS[$i]}" ]]; then
            # Remove existing file if it's not a symlink
            if [[ -f "${ZSH_PATHS[$i]}" && ! -L "${ZSH_PATHS[$i]}" ]]; then
                rm "${ZSH_PATHS[$i]}"
            fi

            # Create symlink
            ln -sf "${GIST_ZSH_PATHS[$i]}" "${ZSH_PATHS[$i]}"
            log_message "Created symlink: ${ZSH_PATHS[$i]} -> ${GIST_ZSH_PATHS[$i]}"
        fi
    done
}

# Function to perform initial setup
initial_setup() {
    log_message "Performing initial setup..."

    # Create gist directory if it doesn't exist
    if [[ ! -d "$GIST_DIR" ]]; then
        mkdir -p "$GIST_DIR"
        log_message "Created directory: $GIST_DIR"
    fi

    # Initialize git repository if it doesn't exist
    if [[ ! -d "$GIST_DIR/.git" ]]; then
        log_message "No git repository found. Please run the install script first."
        exit 1
    fi

    # Create empty files in gist directory if they don't exist
    for path in "${GIST_ZSH_PATHS[@]}"; do
        if [[ ! -f "$path" ]]; then
            touch "$path"
            log_message "Created empty file: $path"
        fi
    done

    # Create symlinks
    create_symlinks

    # Make sure we're in sync with remote to avoid immediate detection of changes
    (cd "$GIST_DIR" && git fetch -q)
    local remote_hash=$(cd "$GIST_DIR" && git rev-parse origin/master 2>/dev/null || git rev-parse origin/main 2>/dev/null)

    # Save the remote hash as our current hash to prevent immediate sync prompts
    echo "$remote_hash" > "$LAST_HASH_FILE"

    log_message "Initial setup complete"
}

# Main function
main() {
    # Create log file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
    fi

    log_message "ZSH Settings Sync started"

    if [[ "$SKIP_INITIAL_CHECKS" == true ]]; then
        log_message "Running in skip-initial-checks mode"
    fi

    # Perform initial setup if needed
    if [[ ! -f "$LAST_HASH_FILE" ]]; then
        initial_setup
        # Add a delay after initial setup to avoid immediate checks
        log_message "Waiting for $SYNC_INTERVAL seconds before first check..."
        sleep "$SYNC_INTERVAL"
    fi

    # Main loop
    while true; do
        # Check for local changes
        local_changes=$(check_local_changes)

        if [[ "$local_changes" == "true" ]]; then
            log_message "Local changes detected"
            prompt_user "push"
        fi

        # Check for remote changes
        if check_remote_changes; then
            log_message "Remote changes detected"
            prompt_user "pull"
        fi

        # After the first loop, disable the skip flag
        if [[ "$SKIP_INITIAL_CHECKS" == true ]]; then
            SKIP_INITIAL_CHECKS=false
            log_message "Disabled skip-initial-checks mode for future runs"
        fi

        # Sleep for the specified interval
        sleep "$SYNC_INTERVAL"
    done
}

# Run the main function
main