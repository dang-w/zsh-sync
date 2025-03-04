# ZSH Settings Sync

A tool to automatically synchronize ZSH shell settings between multiple devices using a GitHub Gist.

## Overview

ZSH Settings Sync provides a seamless way to keep your ZSH shell configuration files synchronized across multiple devices. It uses a GitHub Gist as the central storage and automatically detects and syncs changes in both directions.

This tool creates symlinks between your local ZSH configuration files and a GitHub Gist repository, allowing you to maintain consistent shell settings across all your devices.

## Features

- **Cross-Platform Support**: Works on macOS and Linux/WSL
- **Two-Way Synchronization**: Detects and syncs changes from local to remote and vice versa
- **User-Friendly Notifications**: Prompts before making any changes
- **Conflict Resolution**: Automatically handles merge conflicts
- **Automatic Setup**: Creates necessary symlinks and initial configuration
- **Detailed Logging**: Maintains a log of all sync activities
- **Smart Change Detection**: Ignores whitespace-only changes to prevent unnecessary sync prompts
- **Change Preview**: Shows a diff of changes before pushing or pulling

## Prerequisites

- Git installed and configured
- GitHub account
- ZSH shell installed
- Bash shell (for running the scripts)

## Important: Manual Gist Creation Required

**Before running the installation script, you must manually create a GitHub Gist with your ZSH configuration files.**

### Creating Your GitHub Gist

1. Go to [https://gist.github.com/](https://gist.github.com/)
2. Create a new **secret** gist with the following files:
   - `zshrc` (copy your current ~/.zshrc content)
   - `zshenv` (copy your current ~/.zshenv content, if it exists)
   - `zprofile` (copy your current ~/.zprofile content, if it exists)
   - `zsh_aliases` (copy your current ~/.zsh_aliases content, if it exists)
   - `zsh_functions` (copy your current ~/.zsh_functions content, if it exists)
3. Note the Gist ID from the URL (e.g., `https://gist.github.com/yourusername/abcd1234efgh5678ijkl`)

**Important Notes:**
- The filenames in the Gist must be exactly as shown above (without the leading dot)
- You only need to create files for the ZSH configuration files you actually use
- For files you don't use, you can either omit them or create empty files

## Quick Installation

After creating your GitHub Gist with your ZSH configuration files, run the installation script:

```bash
./zsh-sync/install.sh https://gist.github.com/yourusername/your-gist-id
```

The script will:
- Clone your Gist repository
- Set up the necessary symlinks between your local ZSH files and the Gist files
- Configure automatic startup based on your OS
- Start the sync service

## Manual Installation

If you prefer to set up everything manually:

### 1. Clone the Gist

After creating your GitHub Gist as described above:

```bash
# Create a directory for your ZSH settings
mkdir -p ~/zsh-settings

# Clone the Gist repository
git clone https://gist.github.com/yourusername/your-gist-id.git ~/zsh-settings
```

### 2. Download the Script

1. Clone this repository or download the `zsh-sync` directory
2. Make the script executable:

```bash
chmod +x zsh-sync/zsh-sync.sh
```

### 3. Run the Script

```bash
./zsh-sync/zsh-sync.sh
```

The script will perform an initial setup, creating symlinks between your ZSH settings and the Gist repository.

## Setting Up Automatic Startup

### macOS

1. Copy the provided `com.user.zshsync.plist` file to your LaunchAgents directory:

```bash
cp zsh-sync/com.user.zshsync.plist ~/Library/LaunchAgents/
```

2. Edit the file to update the path to your script:

```bash
sed -i '' "s|/path/to/zsh-sync.sh|$(pwd)/zsh-sync/zsh-sync.sh|g" ~/Library/LaunchAgents/com.user.zshsync.plist
```

3. Load the LaunchAgent:

```bash
launchctl load ~/Library/LaunchAgents/com.user.zshsync.plist
```

### Linux/WSL

1. Add a cron job to run the script periodically:

```bash
(crontab -l 2>/dev/null; echo "*/20 * * * * $(pwd)/zsh-sync/zsh-sync.sh > /dev/null 2>&1") | crontab -
```

This will run the sync script every 20 minutes.

## How It Works

1. **Initial Setup**: The script creates symlinks from your ZSH configuration files to the cloned Gist repository.
2. **Startup Behavior**: After installation, the script waits for the full sync interval (20 minutes) before performing its first check to avoid immediate prompts.
3. **Periodic Checks**: Every 20 minutes, the script checks for changes in both local and remote settings.
4. **Smart Change Detection**: The script ignores whitespace-only changes, preventing unnecessary sync prompts.
5. **Change Detection**: When significant changes are detected, you'll receive a notification asking if you want to sync.
6. **Change Preview**: Before confirming a sync, you'll see a diff showing exactly what changes will be pushed or pulled.
7. **Synchronization**: The script handles pushing local changes to GitHub or pulling remote changes to your local machine.
8. **Conflict Resolution**: If conflicts occur, the script automatically resolves them by keeping your local version and creating backups.

## File Locations

The script manages the following ZSH configuration files:

- `~/.zshrc` - Main ZSH configuration file
- `~/.zshenv` - Environment variables
- `~/.zprofile` - Login shell configuration
- `~/.zsh_aliases` - Aliases (if you use this file)
- `~/.zsh_functions` - Custom functions (if you use this file)

These files are symlinked to their corresponding files in the Gist repository (without the leading dot).

## Customization

You can customize the script by editing the following variables in `zsh-sync.sh`:

- `SYNC_INTERVAL`: Time in seconds between sync checks (default: 1200 seconds / 20 minutes)
- `GIST_DIR`: Location of the cloned Gist repository (default: `~/zsh-settings`)
- `ZSH_PATHS`: Array of ZSH configuration files to sync

If you have additional ZSH configuration files you want to sync, add them to the `ZSH_PATHS` array in the script and also add the corresponding files to your Gist.

## Troubleshooting

### Manual Push Script

If you encounter issues with pushing your changes to GitHub, you can use the included `manual_push.sh` script:

```bash
chmod +x zsh-sync/manual_push.sh
./zsh-sync/manual_push.sh
```

This script provides more detailed output and can help diagnose authentication issues.

### Logs

Check the log file for detailed information:

```bash
cat ~/zsh-settings/sync.log
```

The log file contains timestamps and detailed information about what the script is doing, including when it's skipping checks, detecting changes, and performing synchronization.

### Common Issues

1. **Authentication Issues**: Ensure you have proper Git credentials set up for pushing to GitHub.
   - For HTTPS URLs, you might need a personal access token
   - For SSH, make sure your SSH key is added to GitHub

2. **Symlink Creation Fails**: On some systems, you may need to run the script with sudo to create symlinks.

3. **Changes Not Detected**: Make sure the script is running in the background. Check the log file for any errors.
   - On macOS, verify the LaunchAgent is loaded with: `launchctl list | grep zshsync`
   - On Linux, check your crontab with: `crontab -l | grep zsh-sync`

4. **Gist Not Found**: Verify that you've created the Gist correctly with the proper filenames (without leading dots).

5. **Immediate Sync Prompts**: If you're getting sync prompts immediately after installation:
   - Check the log file to see what's happening
   - Verify that the `.last_hash` file was created in your `~/zsh-settings` directory
   - You can manually create or update this file with: `cd ~/zsh-settings && git rev-parse HEAD > .last_hash`

6. **Popup Dialogs Not Responding**: If you dismiss a popup by clicking the X button instead of one of the buttons, the script will now continue running normally.

## Security Considerations

- The script uses a secret GitHub Gist, which is only accessible to you and people you explicitly share it with.
- Your ZSH settings may contain sensitive information like API keys or tokens. Always use a private Gist.
- Git credentials are stored according to your Git configuration.
- The script creates backups of your existing ZSH configuration files before replacing them with symlinks.

## License

This project is licensed under the MIT License - see the LICENSE file for details.