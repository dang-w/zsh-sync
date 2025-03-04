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
            # Use diff with options to ignore whitespace changes
            if ! diff -q -B -w -Z "${ZSH_PATHS[$i]}" "${GIST_ZSH_PATHS[$i]}" > /dev/null 2>&1; then
                # If there are differences, check if they're only whitespace
                # Create temporary normalized files
                local temp_local=$(mktemp)
                local temp_gist=$(mktemp)

                # Normalize both files (remove all whitespace)
                cat "${ZSH_PATHS[$i]}" | tr -d '[:space:]' > "$temp_local"
                cat "${GIST_ZSH_PATHS[$i]}" | tr -d '[:space:]' > "$temp_gist"

                # Compare the normalized files
                if ! cmp -s "$temp_local" "$temp_gist"; then
                    log_message "Significant changes detected in ${ZSH_PATHS[$i]}"
                    has_changes=true
                else
                    log_message "Only whitespace changes in ${ZSH_PATHS[$i]} - ignoring"
                fi

                # Clean up temp files
                rm "$temp_local" "$temp_gist"
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

    # If the remote hash is different from both the current hash and the last hash, check for non-whitespace changes
    if [[ "$current_hash" != "$remote_hash" && "$last_hash" != "$remote_hash" ]]; then
        log_message "Remote hash ($remote_hash) differs from current hash ($current_hash) and last hash ($last_hash)"

        # Create a temporary branch to check the changes
        (cd "$GIST_DIR" && git branch -q -D temp_check 2>/dev/null || true)
        (cd "$GIST_DIR" && git checkout -q -b temp_check)
        (cd "$GIST_DIR" && git fetch -q origin)

        # Try to merge but don't commit yet
        local merge_output=$(cd "$GIST_DIR" && git merge --no-commit --no-ff origin/master 2>&1 || git merge --no-commit --no-ff origin/main 2>&1)

        # Check if there are any non-whitespace changes
        local has_significant_changes=false

        # For each file in the Gist directory
        for file in "${GIST_ZSH_PATHS[@]}"; do
            if [[ -f "$file" ]]; then
                # Check if this file has changes
                if (cd "$GIST_DIR" && git diff --name-only --staged | grep -q "$(basename "$file")"); then
                    # Check if changes are only whitespace
                    local diff_output=$(cd "$GIST_DIR" && git diff --ignore-all-space --ignore-blank-lines --staged "$(basename "$file")")

                    if [[ -n "$diff_output" ]]; then
                        log_message "Significant changes detected in remote $(basename "$file")"
                        has_significant_changes=true
                        break
                    else
                        log_message "Only whitespace changes in remote $(basename "$file") - ignoring"
                    fi
                fi
            fi
        done

        # Abort the merge and go back to the original branch
        (cd "$GIST_DIR" && git merge --abort 2>/dev/null || true)
        (cd "$GIST_DIR" && git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null)
        (cd "$GIST_DIR" && git branch -q -D temp_check 2>/dev/null || true)

        if [[ "$has_significant_changes" == true ]]; then
            return 0  # Significant changes detected
        else
            # Update the last hash file to avoid detecting these whitespace changes again
            echo "$remote_hash" > "$LAST_HASH_FILE"
            log_message "Only whitespace changes detected in remote - updating hash and skipping pull"
            return 1  # No significant changes
        fi
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

# Function to show a simple diff of changes
show_diff() {
    local action="$1"
    local diff_output=""
    local temp_file=$(mktemp)

    if [[ "$action" == "push" ]]; then
        # Show diff between local files and gist files
        for i in "${!ZSH_PATHS[@]}"; do
            if [[ -f "${ZSH_PATHS[$i]}" && -f "${GIST_ZSH_PATHS[$i]}" ]]; then
                local file_diff=$(diff -u "${GIST_ZSH_PATHS[$i]}" "${ZSH_PATHS[$i]}" | grep -v "^---" | grep -v "^+++" | head -n 20)
                if [[ -n "$file_diff" ]]; then
                    diff_output="${diff_output}Changes in $(basename "${ZSH_PATHS[$i]}"):\n${file_diff}\n\n"
                fi
            fi
        done
    elif [[ "$action" == "pull" ]]; then
        # Show diff between remote and local files
        (cd "$GIST_DIR" && git fetch -q)

        for file in "${GIST_ZSH_PATHS[@]}"; do
            if [[ -f "$file" ]]; then
                local base_name=$(basename "$file")
                local file_diff=$(cd "$GIST_DIR" && git diff --color=never HEAD..origin/master -- "$base_name" 2>/dev/null || git diff --color=never HEAD..origin/main -- "$base_name" 2>/dev/null)
                if [[ -n "$file_diff" ]]; then
                    # Clean up the diff output for display
                    file_diff=$(echo "$file_diff" | grep -v "^diff --git" | grep -v "^index" | grep -v "^---" | grep -v "^+++" | head -n 20)
                    diff_output="${diff_output}Changes in $base_name:\n${file_diff}\n\n"
                fi
            fi
        done
    fi

    # If diff is too long, truncate it
    if [[ $(echo -e "$diff_output" | wc -l) -gt 20 ]]; then
        diff_output="$(echo -e "$diff_output" | head -n 20)\n...(more changes not shown)..."
    fi

    # Return the diff output
    echo -e "$diff_output" > "$temp_file"
    echo "$temp_file"
}

# Function to prompt user for action
prompt_user() {
    local action="$1"
    local response
    local diff_file=$(show_diff "$action")
    local diff_content=$(cat "$diff_file")

    # Remove the temp file after reading it
    rm "$diff_file"

    if [[ "$action" == "push" ]]; then
        show_notification "ZSH Settings Sync" "Local changes detected. Sync to GitHub?"

        # Use AppleScript dialog on macOS, zenity on Linux
        if [[ "$OS_TYPE" == "macOS" ]]; then
            # Create a temporary file with the diff content for AppleScript to display
            local temp_diff_file=$(mktemp)
            echo "$diff_content" > "$temp_diff_file"

            response=$(osascript <<EOF
tell application "System Events"
    set dialogText to do shell script "cat '$temp_diff_file'"
    set theResponse to display dialog "Local ZSH settings have changed. Push to GitHub?\n\nChanges to be pushed:\n" & dialogText buttons {"Cancel", "Push"} default button "Push" with title "ZSH Settings Sync"
    return button returned of theResponse
end tell
EOF
            )

            rm "$temp_diff_file"

            if [[ "$response" == "Push" ]]; then
                push_changes
            else
                log_message "User declined to push changes"
            fi
        else
            # For Linux
            if command -v zenity &> /dev/null; then
                # Create a temporary file with the diff content
                local temp_diff_file=$(mktemp)
                echo "$diff_content" > "$temp_diff_file"

                zenity --text-info --title="ZSH Settings Sync - Changes to Push" --filename="$temp_diff_file" --width=600 --height=400 --ok-label="Push" --cancel-label="Cancel" 2>/dev/null

                rm "$temp_diff_file"

                if [ $? -eq 0 ]; then
                    push_changes
                else
                    log_message "User declined to push changes"
                fi
            else
                # Fallback to terminal prompt
                echo -e "Changes to be pushed:\n$diff_content"
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
            # Create a temporary file with the diff content for AppleScript to display
            local temp_diff_file=$(mktemp)
            echo "$diff_content" > "$temp_diff_file"

            response=$(osascript <<EOF
tell application "System Events"
    set dialogText to do shell script "cat '$temp_diff_file'"
    set theResponse to display dialog "Remote ZSH settings have changed. Pull from GitHub?\n\nChanges to be pulled:\n" & dialogText buttons {"Cancel", "Pull"} default button "Pull" with title "ZSH Settings Sync"
    return button returned of theResponse
end tell
EOF
            )

            rm "$temp_diff_file"

            if [[ "$response" == "Pull" ]]; then
                pull_changes
            else
                log_message "User declined to pull changes"
            fi
        else
            # For Linux
            if command -v zenity &> /dev/null; then
                # Create a temporary file with the diff content
                local temp_diff_file=$(mktemp)
                echo "$diff_content" > "$temp_diff_file"

                zenity --text-info --title="ZSH Settings Sync - Changes to Pull" --filename="$temp_diff_file" --width=600 --height=400 --ok-label="Pull" --cancel-label="Cancel" 2>/dev/null

                rm "$temp_diff_file"

                if [ $? -eq 0 ]; then
                    pull_changes
                else
                    log_message "User declined to pull changes"
                fi
            else
                # Fallback to terminal prompt
                echo -e "Changes to be pulled:\n$diff_content"
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