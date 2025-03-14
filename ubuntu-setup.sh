#!/bin/bash

# Enhanced Ubuntu Setup Script
# Comprehensive system configuration and management tool
# Version: 3.0

#######################################
# INITIALIZATION AND SETUP
#######################################

# Colors for output (used outside dialog screens)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Set up white dialog theme
create_white_dialog_theme() {
  # Create temporary dialogrc file with white theme
  cat > /tmp/white_dialogrc << EOL
# Dialog appearance settings for white theme
screen_color = (WHITE,WHITE,ON)
dialog_color = (BLACK,WHITE,OFF)
title_color = (BLACK,WHITE,ON)
border_color = (BLACK,WHITE,ON)
shadow_color = (BLACK,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,ON)
button_key_inactive_color = (BLACK,WHITE,OFF)
button_label_active_color = (WHITE,BLUE,ON)
button_label_inactive_color = (BLACK,WHITE,OFF)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLACK,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (BLACK,WHITE,ON)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLACK,WHITE,OFF)
tag_selected_color = (WHITE,BLUE,ON)
EOL

  # Set the DIALOGRC environment variable
  export DIALOGRC=/tmp/white_dialogrc
  # Don't call log here as it might not be defined yet
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Dialog theme set to white background"
}

# Call the function to apply white theme
create_white_dialog_theme

# Script information
SCRIPT_NAME="Enhanced Ubuntu Setup"
SCRIPT_VERSION="3.0"
SCRIPT_PATH=$(readlink -f "$0")
SELF_REMOVE=0

# Ensure TERM is properly set for dialog
if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    export TERM=linux
    log "TERM environment variable set to linux"
fi

# Root check - with clear messaging at the start
if [ "$EUID" -ne 0 ]; then
  clear
  echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║                    ADMINISTRATOR PRIVILEGES                    ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${YELLOW}This script requires administrator privileges to run properly.${NC}"
  echo -e "${YELLOW}Please execute the script using sudo:${NC}"
  echo
  echo -e "${GREEN}    sudo $0 ${NC}"
  echo
  exit 1
fi

# Setup backup directory
BACKUP_DIR="$HOME/BACKUP-UBUNTUSETUP"
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/configs"
mkdir -p "$BACKUP_DIR/logs"
mkdir -p "$BACKUP_DIR/ssh_keys"
mkdir -p "$BACKUP_DIR/system_state"
mkdir -p "$BACKUP_DIR/firewall"
mkdir -p "$BACKUP_DIR/network"
mkdir -p "$BACKUP_DIR/disk"
mkdir -p "$BACKUP_DIR/users"

# Log directory
LOG_DIR="$BACKUP_DIR/logs"
MAIN_LOG="$LOG_DIR/main.log"

# Rotate logs if necessary (keep only 5 most recent)
if [ -f "$MAIN_LOG" ]; then
  # Check if we already have 5 logs
  LOG_COUNT=$(ls "$LOG_DIR"/main*.log 2>/dev/null | wc -l)
  if [ "$LOG_COUNT" -ge 5 ]; then
    # Find and remove the oldest log
    OLDEST_LOG=$(ls -t "$LOG_DIR"/main*.log | tail -1)
    rm -f "$OLDEST_LOG"
  fi
  
  # Rename current log with timestamp
  mv "$MAIN_LOG" "$LOG_DIR/main_$(date +%Y%m%d%H%M%S).log"
fi

# Function for logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$MAIN_LOG"
}

log "Script started (version $SCRIPT_VERSION)"

# Function for tracking installed packages
init_package_tracking() {
  local installed_packages_file="$BACKUP_DIR/installed_packages.txt"
  # Create an empty file if it doesn't exist
  if [ ! -f "$installed_packages_file" ]; then
    touch "$installed_packages_file"
  fi
}

track_installed_package() {
  local package_name="$1"
  local installed_packages_file="$BACKUP_DIR/installed_packages.txt"
  
  # Check if the package was already installed before this script was executed
  if ! dpkg -l | grep -q "^ii  $package_name "; then
    # Add the package to the file of installed packages
    echo "$package_name" >> "$installed_packages_file"
  fi
}

# Initialize package tracking
init_package_tracking

# Function for clean exit
cleanup_and_exit() {
  local exit_code=$?
  clear
  if [ $exit_code -ne 0 ]; then
    echo -e "${RED}Script was interrupted by user (CTRL+C).${NC}"
    echo -e "${YELLOW}All active dialog windows will be closed.${NC}"
  fi
  
  # Restore terminal to normal mode
  reset
  
  # Log if necessary
  if [ $exit_code -ne 0 ]; then
    log "Script was interrupted by user via CTRL+C or signal"
  fi
  
  # Remove temporary files if present
  rm -f /tmp/dialog.* 2>/dev/null
  
  # If self-remove is enabled, execute stealth mode
  if [ "${SELF_REMOVE:-0}" = "1" ] && [ $exit_code -eq 0 ]; then
    log "Self-remove mode enabled. Cleanup started."
    
    # Check if we need to remove packages
    local installed_packages_file="$BACKUP_DIR/installed_packages.txt"
    if [ -f "$BACKUP_DIR/stealth_remove_packages" ] && [ -f "$installed_packages_file" ]; then
      if [ -s "$installed_packages_file" ]; then
        log "Removing installed packages..."
        echo -e "${YELLOW}Removing installed packages in stealth mode...${NC}"
        
        # Read packages and remove them
        local packages_to_remove=$(cat "$installed_packages_file")
        if [ ! -z "$packages_to_remove" ]; then
          apt-get purge -y $packages_to_remove >/dev/null 2>&1
          apt-get autoremove -y >/dev/null 2>&1
          log "Packages removed: $packages_to_remove"
        fi
      fi
    fi
    
    # Check if we should keep logs
    if [ ! -f "$BACKUP_DIR/keep_logs" ]; then
      log "Removing log files..."
      find "$LOG_DIR" -type f -not -name "main.log" -delete
      # Keep main.log until the end for final logging
    fi
    
    # Remove the script itself
    log "Self-remove mode enabled. Script will be removed."
    rm -f "$SCRIPT_PATH"
    
    # Final message before removal
    echo -e "${YELLOW}Script has removed itself according to the stealth mode setting.${NC}"
    
    # Remove the main.log last if logs shouldn't be kept
    if [ ! -f "$BACKUP_DIR/keep_logs" ]; then
      rm -rf "$LOG_DIR"
    fi
  fi
  
  exit $exit_code
}

# Add signal handling for clean exit
trap cleanup_and_exit SIGINT SIGTERM EXIT

# Install required packages
check_requirements() {
  local required_packages=("dialog" "curl" "wget" "gnupg" "apt-transport-https" "ca-certificates" "lsb-release" "python3" "python3-pip" "jq" "smartmontools" "iftop" "htop" "dstat")
  local missing_packages=()
  
  for pkg in "${required_packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
      missing_packages+=("$pkg")
      # Track the package if it will be installed
      if [[ " ${missing_packages[*]} " =~ " ${pkg} " ]]; then
        track_installed_package "$pkg"
      fi
    fi
  done
  
  if [ ${#missing_packages[@]} -gt 0 ]; then
    echo -e "${YELLOW}Installing required packages: ${missing_packages[*]}${NC}"
    apt update
    apt install -y "${missing_packages[@]}"
    log "Required packages installed: ${missing_packages[*]}"
  fi
}

# Install required packages
check_requirements

# Install dialog if needed
if ! command -v dialog &> /dev/null; then
    apt update
    apt install -y dialog
    track_installed_package "dialog"
    log "Dialog installed"
    
    # Verify dialog is working
    if ! dialog --version >/dev/null 2>&1; then
        echo "Error: Dialog installation failed or not working properly"
        exit 1
    fi
fi

# Install asciinema if needed for terminal recording
if ! command -v asciinema &> /dev/null; then
    apt update
    apt install -y asciinema
    track_installed_package "asciinema"
    log "Asciinema installed"
fi

# Install python-tabulate for better table formatting
if ! python3 -c "import tabulate" 2>/dev/null; then
    echo "Installing python3-tabulate package..."
    apt update
    apt install -y python3-tabulate
    track_installed_package "python3-tabulate"
    log "Python tabulate installed via apt"
    
    # Verify installation
    if ! python3 -c "import tabulate" 2>/dev/null; then
        echo "Error: Failed to install python3-tabulate package"
        log "Failed to install python3-tabulate package"
        exit 1
    fi
fi

# Verify tabulate installation
if ! python3 -c "import tabulate" 2>/dev/null; then
    echo "Error: Python tabulate module failed to install or import"
    log "Python tabulate module failed to install or import"
    exit 1
fi

# Add helper script to generate ASCII tables
cat > /tmp/generate_table.py << 'EOL'
#!/usr/bin/env python3
import sys
import json
from tabulate import tabulate

def generate_table(data_json, headers='keys', tablefmt='grid'):
    try:
        data = json.loads(data_json)
        if isinstance(data, dict):
            # Convert dict to list of key-value pairs
            data = [{"Key": k, "Value": v} for k, v in data.items()]
        
        return tabulate(data, headers=headers, tablefmt=tablefmt)
    except Exception as e:
        return f"Error generating table: {str(e)}"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        data_json = sys.argv[1]
        headers = sys.argv[2] if len(sys.argv) > 2 else 'keys'
        tablefmt = sys.argv[3] if len(sys.argv) > 3 else 'grid'
        print(generate_table(data_json, headers, tablefmt))
    else:
        print("Usage: generate_table.py '<json_data>' [headers] [tablefmt]")
EOL
chmod +x /tmp/generate_table.py

# Function to generate ASCII tables from data
generate_ascii_table() {
    local data="$1"
    local headers="${2:-keys}"
    local format="${3:-grid}"
    
    python3 /tmp/generate_table.py "$data" "$headers" "$format"
}

# Function to display banner in terminal (for non-dialog screens)
show_banner() {
  clear
  echo -e "${BLUE}"
  echo "███████╗███╗   ██╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗███████╗██████╗ "
  echo "██╔════╝████╗  ██║██║  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝██╔══██╗"
  echo "█████╗  ██╔██╗ ██║███████║███████║██╔██╗ ██║██║     █████╗  ██║  ██║"
  echo "██╔══╝  ██║╚██╗██║██╔══██║██╔══██║██║╚██╗██║██║     ██╔══╝  ██║  ██║"
  echo "███████╗██║ ╚████║██║  ██║██║  ██║██║ ╚████║╚██████╗███████╗██████╔╝"
  echo "╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═════╝ "
  echo -e "${NC}"
  echo -e "${YELLOW}=-=-=-=-=-=-=-=- Ubuntu Setup Script v$SCRIPT_VERSION =-=-=-=-=-=-=-=-${NC}"
  echo
}

# Function to display messages in dialog and also write to log
dialog_info() {
  local title="$1"
  local message="$2"
  
  log "$title: $message"
  if ! dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --msgbox "$message" 20 80 2>/dev/null; then
    echo -e "\n${YELLOW}$title:${NC} $message\n"
    echo "Press Enter to continue..."
    read
  fi
}

# Function to ask for confirmation with dialog
dialog_confirm() {
  local title="$1"
  local message="$2"
  
  dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --yesno "$message" 15 70
  return $?
}

# Function to ask for input with dialog
dialog_input() {
  local title="$1"
  local message="$2"
  local default="$3"
  local result
  
  result=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --inputbox "$message" 15 70 "$default" 3>&1 1>&2 2>&3)
  echo "$result"
}

# Function to ask for multiline input
dialog_textarea() {
  local title="$1"
  local message="$2"
  local default="$3"
  local result
  
  # Create temporary file with default content
  local temp_file=$(mktemp)
  echo "$default" > "$temp_file"
  
  result=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --editbox "$temp_file" 20 80 3>&1 1>&2 2>&3)
  
  # Clean up temp file
  rm -f "$temp_file"
  
  echo "$result"
}

# Function to choose from a menu with dialog
dialog_menu() {
  local title="$1"
  local message="$2"
  shift 2
  local options=("$@")
  local choice
  
  choice=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --menu "$message" 25 80 16 "${options[@]}" 3>&1 1>&2 2>&3)
  echo "$choice"
}

# Function for choosing from a radiolist
dialog_radiolist() {
  local title="$1"
  local message="$2"
  shift 2
  local options=("$@")
  local choice
  
  choice=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --radiolist "$message" 25 80 16 "${options[@]}" 3>&1 1>&2 2>&3)
  echo "$choice"
}

# Function for safe output to a file
safe_output() {
  local content="$1"
  local file="$2"
  
  echo "$content" > "$file"
}

# Function to get user list (non-system users)
get_users() {
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  local options=()
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+=("$i" "${user_list[$i]}")
  done
  
  echo "${options[@]}"
}

# Function to display progress window
show_progress() {
  local title="$1"
  local cmd="$2"
  
  (
    echo "0"; sleep 1
    eval "$cmd" >/dev/null 2>&1
    echo "100"
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "$title" --gauge "Working..." 10 70 0
}

#######################################
# SYSTEM UPDATE FUNCTIONS
#######################################

# Function for system update
update_system() {
  log "System update started"
  
  # Ask for confirmation
  if ! dialog_confirm "Update System" "Do you want to proceed with updating the system?"; then
    log "System update cancelled by user"
    return
  fi
  
  # Create system state backup first
  mkdir -p "$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)"
  dpkg --get-selections > "$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)/package_selections.txt"
  apt-mark showhold > "$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)/held_packages.txt"
  cp /etc/apt/sources.list "$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)/sources.list"
  
  # Logs
  local update_log="$LOG_DIR/update_$(date +%Y%m%d%H%M%S).log"
  
  # Run update with progress indicator
  (
    echo "10"; echo "XXX"; echo "Fetching updates..."; echo "XXX"
    apt update >> "$update_log" 2>&1
    
    echo "30"; echo "XXX"; echo "Upgrading system..."; echo "XXX"
    apt upgrade -y >> "$update_log" 2>&1
    
    echo "50"; echo "XXX"; echo "Performing distribution upgrade..."; echo "XXX"
    apt dist-upgrade -y >> "$update_log" 2>&1
    
    echo "70"; echo "XXX"; echo "Installing phased updates..."; echo "XXX"
    apt -o APT::Get::Always-Include-Phased-Updates=true upgrade -y >> "$update_log" 2>&1
    
    echo "90"; echo "XXX"; echo "Cleaning up unnecessary packages..."; echo "XXX"
    apt autoremove -y >> "$update_log" 2>&1
    apt autoclean >> "$update_log" 2>&1
    
    echo "100"; echo "XXX"; echo "System update completed"; echo "XXX"
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "System Update" --gauge "Updates are being performed..." 10 70 0

  log "System update completed"
  
  # Create post-update system state
  mkdir -p "$BACKUP_DIR/system_state/post_update_$(date +%Y%m%d)"
  dpkg --get-selections > "$BACKUP_DIR/system_state/post_update_$(date +%Y%m%d)/package_selections.txt"
  
  # Calculate change stats
  local new_packages=$(diff -u "$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)/package_selections.txt" "$BACKUP_DIR/system_state/post_update_$(date +%Y%m%d)/package_selections.txt" | grep ^+[^+] | wc -l)
  local updated_packages=$(grep "upgraded," "$update_log" | awk '{print $1}')
  local removed_packages=$(diff -u "$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)/package_selections.txt" "$BACKUP_DIR/system_state/post_update_$(date +%Y%m%d)/package_selections.txt" | grep ^-[^-] | wc -l)
  
  # Format update summary in table format
  local update_summary="
System has been updated.

+----------------+-------------+
| Metric         | Count       |
+----------------+-------------+
| New Packages   | $new_packages           |
| Updated        | $updated_packages           |
| Removed        | $removed_packages           |
+----------------+-------------+

Details have been saved to $update_log

A backup of your system state before the update is stored in:
$BACKUP_DIR/system_state/pre_update_$(date +%Y%m%d)
"

  dialog_info "System Update" "$update_summary"
}

# Function for configuring automatic updates
configure_auto_updates() {
  log "Automatic updates configuration started"
  
  # Check if unattended-upgrades is installed
  if ! dpkg -l | grep -q "^ii  unattended-upgrades "; then
    if dialog_confirm "Install Unattended Upgrades" "The unattended-upgrades package is not installed. This package is needed to configure automatic updates.\n\nDo you want to install it now?"; then
      apt update
      apt install -y unattended-upgrades
      track_installed_package "unattended-upgrades"
      log "Unattended-upgrades package installed"
    else
      log "Unattended-upgrades installation cancelled"
      return
    fi
  fi
  
  # Backup current configuration
  mkdir -p "$BACKUP_DIR/system_state/auto_updates"
  cp /etc/apt/apt.conf.d/20auto-upgrades "$BACKUP_DIR/system_state/auto_updates/20auto-upgrades.backup" 2>/dev/null
  cp /etc/apt/apt.conf.d/50unattended-upgrades "$BACKUP_DIR/system_state/auto_updates/50unattended-upgrades.backup" 2>/dev/null
  
  # Current status
  local current_status="Unknown"
  if [ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]; then
    if grep -q "APT::Periodic::Update-Package-Lists \"1\"" /etc/apt/apt.conf.d/20auto-upgrades && \
       grep -q "APT::Periodic::Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades; then
      current_status="Enabled"
    else
      current_status="Disabled"
    fi
  else
    current_status="Not Configured"
  fi
  
  # Get auto-update settings
  local auto_update_action=$(dialog_menu "Automatic Updates" "Current Status: $current_status\n\nChoose an option:" \
    "enable" "Enable automatic updates" \
    "disable" "Disable automatic updates" \
    "configure" "Configure update settings" \
    "status" "View current configuration" \
    "back" "Return to previous menu")
  
  case $auto_update_action in
    enable)
      # Enable automatic updates
      cat > /etc/apt/apt.conf.d/20auto-upgrades << EOL
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOL
      log "Automatic updates enabled"
      dialog_info "Automatic Updates" "Automatic updates have been enabled.\n\nYour system will now automatically check for and install security updates."
      ;;
    disable)
      # Disable automatic updates
      cat > /etc/apt/apt.conf.d/20auto-upgrades << EOL
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::AutocleanInterval "0";
EOL
      log "Automatic updates disabled"
      dialog_info "Automatic Updates" "Automatic updates have been disabled.\n\nYour system will no longer automatically install updates."
      ;;
    configure)
      # Configure update settings
      local config_option=$(dialog_menu "Update Configuration" "Choose what to configure:" \
        "frequency" "Set update frequency" \
        "updates" "Configure which updates to install" \
        "email" "Set email notifications" \
        "reboot" "Configure automatic reboot" \
        "back" "Return to previous menu")
      
      case $config_option in
        frequency)
          local frequency=$(dialog_radiolist "Update Frequency" "How often should the system check for updates?" \
            "1" "Daily" "on" \
            "2" "Every 2 days" "off" \
            "7" "Weekly" "off" \
            "14" "Bi-weekly" "off")
          
          if [ -n "$frequency" ]; then
            sed -i "s/APT::Periodic::Update-Package-Lists \"[0-9]*\"/APT::Periodic::Update-Package-Lists \"$frequency\"/" /etc/apt/apt.conf.d/20auto-upgrades
            log "Update frequency set to $frequency days"
            dialog_info "Update Frequency" "Update frequency has been set to $frequency days."
          fi
          ;;
        updates)
          local update_types=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Update Types" \
            --checklist "Select the types of updates to install automatically:" 15 70 10 \
            "security" "Security updates" "on" \
            "updates" "Recommended updates" "off" \
            "proposed" "Pre-released updates" "off" \
            "backports" "Backported updates" "off" 3>&1 1>&2 2>&3)
          
          if [ $? -eq 0 ]; then
            # Create default configuration if it doesn't exist
            if [ ! -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
              cp /usr/share/unattended-upgrades/50unattended-upgrades /etc/apt/apt.conf.d/
            fi
            
            # Update the configuration
            sed -i '/Unattended-Upgrade::Allowed-Origins/,/};/c\Unattended-Upgrade::Allowed-Origins {\n};' /etc/apt/apt.conf.d/50unattended-upgrades
            
            # Add the selected repositories
            if [[ "$update_types" == *"security"* ]]; then
              sed -i '/Unattended-Upgrade::Allowed-Origins {/a\  "${distro_id}:${distro_codename}-security";' /etc/apt/apt.conf.d/50unattended-upgrades
            fi
            if [[ "$update_types" == *"updates"* ]]; then
              sed -i '/Unattended-Upgrade::Allowed-Origins {/a\  "${distro_id}:${distro_codename}-updates";' /etc/apt/apt.conf.d/50unattended-upgrades
            fi
            if [[ "$update_types" == *"proposed"* ]]; then
              sed -i '/Unattended-Upgrade::Allowed-Origins {/a\  "${distro_id}:${distro_codename}-proposed";' /etc/apt/apt.conf.d/50unattended-upgrades
            fi
            if [[ "$update_types" == *"backports"* ]]; then
              sed -i '/Unattended-Upgrade::Allowed-Origins {/a\  "${distro_id}:${distro_codename}-backports";' /etc/apt/apt.conf.d/50unattended-upgrades
            fi
            
            log "Update types configured: $update_types"
            dialog_info "Update Types" "The system has been configured to automatically install the selected update types."
          fi
          ;;
        email)
          local email=$(dialog_input "Email Notifications" "Enter an email address to receive update notifications (leave empty to disable):" "")
          
          # Update the configuration
          if [ ! -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
            cp /usr/share/unattended-upgrades/50unattended-upgrades /etc/apt/apt.conf.d/
          fi
          
          if [ -z "$email" ]; then
            # Disable email notifications
            sed -i 's/^\/\/Unattended-Upgrade::Mail "/\/\/Unattended-Upgrade::Mail "/' /etc/apt/apt.conf.d/50unattended-upgrades
            sed -i 's/^Unattended-Upgrade::Mail "/\/\/Unattended-Upgrade::Mail "/' /etc/apt/apt.conf.d/50unattended-upgrades
            log "Email notifications disabled"
            dialog_info "Email Notifications" "Email notifications have been disabled."
          else
            # Enable email notifications
            if grep -q "Unattended-Upgrade::Mail" /etc/apt/apt.conf.d/50unattended-upgrades; then
              sed -i "s/^.*Unattended-Upgrade::Mail .*/Unattended-Upgrade::Mail \"$email\";/" /etc/apt/apt.conf.d/50unattended-upgrades
            else
              echo "Unattended-Upgrade::Mail \"$email\";" >> /etc/apt/apt.conf.d/50unattended-upgrades
            fi
            log "Email notifications set to: $email"
            dialog_info "Email Notifications" "Email notifications will be sent to: $email"
          fi
          ;;
        reboot)
          local reboot_option=$(dialog_menu "Automatic Reboot" "Configure automatic reboot after updates:" \
            "disable" "Disable automatic reboot" \
            "enable" "Enable automatic reboot" \
            "time" "Set specific time for reboot" \
            "back" "Return to previous menu")
          
          case $reboot_option in
            disable)
              if [ ! -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
                cp /usr/share/unattended-upgrades/50unattended-upgrades /etc/apt/apt.conf.d/
              fi
              
              sed -i 's/^Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "false";/' /etc/apt/apt.conf.d/50unattended-upgrades
              sed -i 's/^\/\/Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "false";/' /etc/apt/apt.conf.d/50unattended-upgrades
              
              log "Automatic reboot disabled"
              dialog_info "Automatic Reboot" "Automatic reboot after updates has been disabled."
              ;;
            enable)
              if [ ! -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
                cp /usr/share/unattended-upgrades/50unattended-upgrades /etc/apt/apt.conf.d/
              fi
              
              sed -i 's/^Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "true";/' /etc/apt/apt.conf.d/50unattended-upgrades
              sed -i 's/^\/\/Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "true";/' /etc/apt/apt.conf.d/50unattended-upgrades
              
              log "Automatic reboot enabled"
              dialog_info "Automatic Reboot" "Automatic reboot after updates has been enabled."
              ;;
            time)
              local reboot_time=$(dialog_input "Reboot Time" "Enter the time for automatic reboot (format: HH:MM):" "02:00")
              
              if [ -n "$reboot_time" ]; then
                if [ ! -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
                  cp /usr/share/unattended-upgrades/50unattended-upgrades /etc/apt/apt.conf.d/
                fi
                
                sed -i 's/^Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "true";/' /etc/apt/apt.conf.d/50unattended-upgrades
                sed -i 's/^\/\/Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "true";/' /etc/apt/apt.conf.d/50unattended-upgrades
                
                sed -i "s/^Unattended-Upgrade::Automatic-Reboot-Time .*/Unattended-Upgrade::Automatic-Reboot-Time \"$reboot_time\";/" /etc/apt/apt.conf.d/50unattended-upgrades
                sed -i "s/^\/\/Unattended-Upgrade::Automatic-Reboot-Time .*/Unattended-Upgrade::Automatic-Reboot-Time \"$reboot_time\";/" /etc/apt/apt.conf.d/50unattended-upgrades
                
                log "Automatic reboot time set to: $reboot_time"
                dialog_info "Automatic Reboot" "Automatic reboot time has been set to $reboot_time."
              fi
              ;;
            back|"")
              ;;
          esac
          ;;
        back|"")
          ;;
      esac
      ;;
    status)
      # View current configuration
      local status_output=""
      
      if [ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]; then
        status_output+="=== 20auto-upgrades ===\n"
        status_output+=$(cat /etc/apt/apt.conf.d/20auto-upgrades)
        status_output+="\n\n"
      else
        status_output+="20auto-upgrades file not found. Automatic updates may not be configured.\n\n"
      fi
      
      if [ -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
        status_output+="=== 50unattended-upgrades (relevant parts) ===\n"
        # Extract and display relevant parts
        status_output+="Allowed Origins:\n"
        status_output+=$(sed -n '/Unattended-Upgrade::Allowed-Origins/,/};/p' /etc/apt/apt.conf.d/50unattended-upgrades)
        status_output+="\n\nEmail Notifications:\n"
        status_output+=$(grep -A 1 "Unattended-Upgrade::Mail" /etc/apt/apt.conf.d/50unattended-upgrades || echo "Not configured")
        status_output+="\n\nAutomatic Reboot:\n"
        status_output+=$(grep -A 1 "Unattended-Upgrade::Automatic-Reboot" /etc/apt/apt.conf.d/50unattended-upgrades || echo "Not configured")
        status_output+=$(grep -A 1 "Unattended-Upgrade::Automatic-Reboot-Time" /etc/apt/apt.conf.d/50unattended-upgrades || echo "")
      else
        status_output+="50unattended-upgrades file not found. Detailed settings are not configured."
      fi
      
      dialog_info "Current Configuration" "$status_output"
      ;;
    back|"")
      log "Automatic updates configuration cancelled by user"
      return
      ;;
  esac
}

# Function for changing hostname
change_hostname() {
  log "Change hostname started"
  
  # Ask for confirmation
  if ! dialog_confirm "Change Hostname" "Do you want to proceed with changing the hostname?"; then
    log "Change hostname cancelled by user"
    return
  fi
  
  # Display current hostname
  current_hostname=$(hostname)
  log "Current hostname: $current_hostname"
  
  # Ask for new hostname
  new_hostname=$(dialog_input "Hostname" "Enter the new hostname:" "$current_hostname")
  
  if [ -z "$new_hostname" ]; then
    dialog_info "Hostname" "No hostname entered. Hostname remains unchanged."
    log "No new hostname entered"
    return
  fi
  
  # Validate hostname format
  if ! [[ "$new_hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
    dialog_info "Invalid Hostname" "The hostname must contain only letters, numbers, and hyphens, and cannot start or end with a hyphen."
    log "Invalid hostname format: $new_hostname"
    return
  fi
  
  log "New hostname: $new_hostname"
  
  # Backup current configuration
  mkdir -p "$BACKUP_DIR/system_state"
  cp /etc/hostname "$BACKUP_DIR/system_state/hostname.backup.$(date +%Y%m%d%H%M%S)"
  cp /etc/hosts "$BACKUP_DIR/system_state/hosts.backup.$(date +%Y%m%d%H%M%S)"
  
  # Change hostname
  hostnamectl set-hostname "$new_hostname"
  
  # Update hosts file
  sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
  
  log "Hostname changed from $current_hostname to $new_hostname"
  dialog_info "Hostname" "Hostname has been changed from\n$current_hostname\nto\n$new_hostname\n\nA restart may be required for the change to take effect everywhere."
}

#######################################
# USER MANAGEMENT FUNCTIONS
#######################################

# Function for changing user password without interactive passwd
change_password() {
  log "User password change started"
  
  # Ask for confirmation
  if ! dialog_confirm "Change Password" "Do you want to proceed with changing a user password?"; then
    log "Change password cancelled by user"
    return
  fi
  
  # Create an array of usernames
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    dialog_info "Change Password" "No normal users found on the system."
    log "No normal users found"
    return
  fi
  
  # Build menu options with users
  local options=()
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+=("$i" "${user_list[$i]}")
  done
  
  # Let user choose
  local selection=$(dialog_menu "Select User" "Choose a user to change password:" "${options[@]}")
  
  if [ -z "$selection" ]; then
    log "User selection cancelled"
    return
  fi
  
  local username="${user_list[$selection]}"
  log "Selected user: $username"
  
  # Ask password via dialog
  password1=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Password" --insecure --passwordbox "Enter the new password for $username:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    log "Password input cancelled"
    return
  fi
  
  # Ask confirmation
  password2=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Confirm Password" --insecure --passwordbox "Enter the password again:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    log "Password confirmation cancelled"
    return
  fi
  
  # Check if passwords match
  if [ "$password1" != "$password2" ]; then
    dialog_info "Change Password" "The passwords do not match. Please try again."
    log "Passwords do not match"
    return
  fi
  
  # Check if password is empty
  if [ -z "$password1" ]; then
    dialog_info "Change Password" "Empty password is not allowed."
    log "Empty password detected"
    return
  fi
  
  # Change password with chpasswd
  echo "$username:$password1" | chpasswd
  passwd_exit=$?
  
  # Create backup metadata (not the password itself)
  mkdir -p "$BACKUP_DIR/users"
  echo "Password changed for $username on $(date)" >> "$BACKUP_DIR/users/password_changes.log"
  
  if [ $passwd_exit -ne 0 ]; then
    dialog_info "Change Password" "Password change failed. Check the logs for more information."
    log "Password change for $username failed with code: $passwd_exit"
  else
    dialog_info "Change Password" "Password for $username has been successfully changed."
    log "Password for $username has been successfully changed"
  fi
}

# Function for user dashboard
user_dashboard() {
  log "User dashboard started"
  
  # Build options with users
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    dialog_info "User Dashboard" "No normal users found on the system."
    log "No normal users found"
    return
  fi
  
  # Build menu options with users
  local options=()
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+=("$i" "${user_list[$i]}")
  done
  
  # Let user choose
  local selection=$(dialog_menu "Select User" "Choose a user to view:" "${options[@]}")
  
  if [ -z "$selection" ]; then
    log "User selection cancelled"
    return
  fi
  
  local username="${user_list[$selection]}"
  log "Selected user for dashboard: $username"
  
  # Gather user information
  local user_id=$(id -u "$username")
  local group_id=$(id -g "$username")
  local group_name=$(id -gn "$username")
  local all_groups=$(id -Gn "$username" | tr ' ' ', ')
  local shell=$(getent passwd "$username" | cut -d: -f7)
  local home_dir=$(getent passwd "$username" | cut -d: -f6)
  local last_login=$(last "$username" -1 | head -1 | awk '{print $4, $5, $6, $7}')
  local account_expiry=$(chage -l "$username" | grep "Account expires" | cut -d: -f2-)
  local passwd_expiry=$(chage -l "$username" | grep "Password expires" | cut -d: -f2-)
  local sudo_access="No"
  
  # Check sudo rights
  if groups "$username" | grep -q "\<sudo\>"; then
    sudo_access="Yes (via sudo group)"
  elif [ -f "/etc/sudoers.d/$username" ]; then
    sudo_access="Yes (via /etc/sudoers.d/$username)"
  elif grep -q "^$username" /etc/sudoers; then
    sudo_access="Yes (via /etc/sudoers file)"
  fi
  
  # Create JSON data for the table
  local user_data='{
    "User Information": [
      {"Property": "Username", "Value": "'$username'"},
      {"Property": "User ID", "Value": "'$user_id'"},
      {"Property": "Primary Group", "Value": "'$group_name' (ID: '$group_id')"},
      {"Property": "All Groups", "Value": "'$all_groups'"},
      {"Property": "Shell", "Value": "'$shell'"},
      {"Property": "Home Directory", "Value": "'$home_dir'"},
      {"Property": "Last Login", "Value": "'$last_login'"},
      {"Property": "Account Expires", "Value": "'$account_expiry'"},
      {"Property": "Password Expires", "Value": "'$passwd_expiry'"},
      {"Property": "Sudo Rights", "Value": "'$sudo_access'"}
    ]
  }'
  
  # System activity of this user
  local user_processes=$(ps -u "$username" --no-headers | wc -l)
  
  # Disk usage
  local disk_usage=$(du -sh "$home_dir" 2>/dev/null | cut -f1)
  
  # Additional metrics
  local activity_data='{
    "Activity Metrics": [
      {"Metric": "Active Processes", "Value": "'$user_processes'"},
      {"Metric": "Disk Usage (home)", "Value": "'$disk_usage'"}
    ]
  }'
  
  # Format user info table
  local user_info=$(python3 -c "
import json
from tabulate import tabulate
data = json.loads('$user_data')
print(tabulate(data['User Information'], headers='keys', tablefmt='grid'))
")

  # Format activity metrics table
  local activity_info=$(python3 -c "
import json
from tabulate import tabulate
data = json.loads('$activity_data')
print(tabulate(data['Activity Metrics'], headers='keys', tablefmt='grid'))
")

  # Format the complete user dashboard
  local dashboard_info="══════════════════ USER DASHBOARD ══════════════════\n"
  dashboard_info+="$user_info\n\n"
  dashboard_info+="════════════════ ACTIVITY METRICS ════════════════\n"
  dashboard_info+="$activity_info\n"
  
  # Show user information
  dialog_info "User: $username" "$dashboard_info"
  
  # Options for user management
  local action=$(dialog_menu "User Management" "Choose an action for $username:" \
    "passwd" "Change password" \
    "groups" "Manage groups" \
    "sudo" "Manage sudo rights" \
    "expire" "Set account/password expiry" \
    "lock" "Lock/unlock account" \
    "shell" "Change login shell" \
    "quota" "Manage disk quota" \
    "back" "Back to main menu")
  
  case $action in
    passwd)
      change_password
      ;;
    groups)
      manage_user_groups "$username"
      ;;
    sudo)
      manage_sudo_access "$username"
      ;;
    expire)
      manage_account_expiry "$username"
      ;;
    lock)
      manage_account_lock "$username"
      ;;
    shell)
      change_user_shell "$username"
      ;;
    quota)
      manage_user_quota "$username"
      ;;
    back|*)
      return
      ;;
  esac
}

# Function for account locking and unlocking
manage_account_lock() {
  local username="$1"
  log "Account lock/unlock started for: $username"
  
  # Check current lock status
  local is_locked=0
  passwd -S "$username" | grep -q "L" && is_locked=1
  
  if [ $is_locked -eq 1 ]; then
    local status_msg="Account is currently LOCKED"
    local action_msg="Do you want to UNLOCK this account?"
    local action="unlock"
  else
    local status_msg="Account is currently UNLOCKED"
    local action_msg="Do you want to LOCK this account?"
    local action="lock"
  fi
  
  # Ask for confirmation
  if dialog_confirm "Account Status" "$status_msg\n\n$action_msg"; then
    if [ $is_locked -eq 1 ]; then
      # Unlock account
      passwd -u "$username"
      log "Account unlocked: $username"
      dialog_info "Account Unlocked" "The account for $username has been unlocked and can now be used."
    else
      # Lock account
      passwd -l "$username"
      log "Account locked: $username"
      dialog_info "Account Locked" "The account for $username has been locked and cannot be used until unlocked."
    fi
  else
    log "Account $action cancelled for $username"
  fi
}

# Function for changing user shell
change_user_shell() {
  local username="$1"
  log "Shell change started for: $username"
  
  # Get current shell
  local current_shell=$(getent passwd "$username" | cut -d: -f7)
  
  # Get available shells
  local available_shells=()
  while IFS= read -r shell; do
    available_shells+=("$shell" "")
  done < /etc/shells
  
  # Build options with available shells
  local shell_options=()
  for shell in "${available_shells[@]}"; do
    if [ -n "$shell" ] && [ "$shell" != "" ]; then
      if [ "$shell" = "$current_shell" ]; then
        shell_options+=("$shell" "Current shell" "on")
      else
        shell_options+=("$shell" "Available shell" "off")
      fi
    fi
  done
  
  # Let user choose a new shell
  local new_shell=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
    --title "Change Shell for $username" \
    --radiolist "Current shell: $current_shell\n\nSelect a new shell:" 20 70 10 \
    "${shell_options[@]}" 3>&1 1>&2 2>&3)
  
  if [ -z "$new_shell" ]; then
    log "Shell selection cancelled for $username"
    return
  fi
  
  # Check if shell exists and is executable
  if [ ! -x "$new_shell" ]; then
    dialog_info "Invalid Shell" "The selected shell '$new_shell' does not exist or is not executable."
    log "Invalid shell selected for $username: $new_shell"
    return
  fi
  
  # Change the shell
  chsh -s "$new_shell" "$username"
  
  log "Shell changed for $username from $current_shell to $new_shell"
  dialog_info "Shell Changed" "The login shell for $username has been changed from $current_shell to $new_shell."
}

# Function for managing user disk quota
manage_user_quota() {
  local username="$1"
  log "Quota management started for user: $username"
  
  # Check if quota is installed
  if ! command -v quota &> /dev/null || ! command -v setquota &> /dev/null; then
    if dialog_confirm "Install Quota" "Disk quota tools are not installed. Do you want to install them now?"; then
      apt update
      apt install -y quota quotatool
      track_installed_package "quota"
      track_installed_package "quotatool"
      log "Quota tools installed"
    else
      log "Quota tools installation cancelled"
      return
    fi
  fi
  
  # Check if any filesystem has quotas enabled
  local has_quotas=0
  if grep -q "quota" /etc/fstab; then
    has_quotas=1
  fi
  
  if [ $has_quotas -eq 0 ]; then
    if dialog_confirm "Enable Quota" "No filesystems have quota enabled. Do you want to enable quota on a filesystem now?"; then
      enable_filesystem_quota
    else
      log "Quota enabling cancelled"
      return
    fi
  fi
  
  # Find filesystems with quota enabled
  local quota_filesystems=()
  while read -r line; do
    if [[ "$line" == *"quota"* ]]; then
      local fs=$(echo "$line" | awk '{print $2}')
      quota_filesystems+=("$fs")
    fi
  done < /etc/fstab
  
  if [ ${#quota_filesystems[@]} -eq 0 ]; then
    dialog_info "No Quota Filesystems" "No filesystems with quota enabled were found. Please enable quota on a filesystem first."
    log "No quota filesystems found"
    return
  fi
  
  # Build options with filesystems
  local fs_options=()
  for fs in "${quota_filesystems[@]}"; do
    fs_options+=("$fs" "Filesystem with quota")
  done
  
  # Let user choose a filesystem
  local selected_fs=$(dialog_menu "Select Filesystem" "Choose a filesystem to set quota for $username:" "${fs_options[@]}")
  
  if [ -z "$selected_fs" ]; then
    log "Filesystem selection cancelled"
    return
  fi
  
  # Get current quota
  local current_quota=$(quota -u "$username" 2>/dev/null || echo "No quota set")
  
  dialog_info "Current Quota" "Current quota for user $username on $selected_fs:\n\n$current_quota"
  
  # Ask for quota limits
  local soft_blocks=$(dialog_input "Soft Block Limit" "Enter the soft block limit in KB (0 = no limit):" "0")
  if [ -z "$soft_blocks" ]; then
    soft_blocks=0
  fi
  
  local hard_blocks=$(dialog_input "Hard Block Limit" "Enter the hard block limit in KB (0 = no limit):" "0")
  if [ -z "$hard_blocks" ]; then
    hard_blocks=0
  fi
  
  local soft_inodes=$(dialog_input "Soft Inode Limit" "Enter the soft inode limit (files count) (0 = no limit):" "0")
  if [ -z "$soft_inodes" ]; then
    soft_inodes=0
  fi
  
  local hard_inodes=$(dialog_input "Hard Inode Limit" "Enter the hard inode limit (files count) (0 = no limit):" "0")
  if [ -z "$hard_inodes" ]; then
    hard_inodes=0
  fi
  
  # Set the quota
  setquota -u "$username" "$soft_blocks" "$hard_blocks" "$soft_inodes" "$hard_inodes" "$selected_fs"
  
  log "Quota set for $username on $selected_fs: blocks=$soft_blocks/$hard_blocks, inodes=$soft_inodes/$hard_inodes"
  
  # Format quota information in readable table
  local human_soft_blocks=$(numfmt --to=iec-i --suffix=B --format="%.1f" $(($soft_blocks * 1024)))
  local human_hard_blocks=$(numfmt --to=iec-i --suffix=B --format="%.1f" $(($hard_blocks * 1024)))
  
  local quota_info='{
    "Quota Settings": [
      {"Limit Type": "Disk Space (Soft)", "Value": "'$human_soft_blocks'"},
      {"Limit Type": "Disk Space (Hard)", "Value": "'$human_hard_blocks'"},
      {"Limit Type": "Files Count (Soft)", "Value": "'$soft_inodes'"},
      {"Limit Type": "Files Count (Hard)", "Value": "'$hard_inodes'"}
    ]
  }'
  
  # Format quota info table
  local formatted_quota=$(python3 -c "
import json
from tabulate import tabulate
data = json.loads('$quota_info')
print(tabulate(data['Quota Settings'], headers='keys', tablefmt='grid'))
")
  
  dialog_info "Quota Set" "Quota has been set for user $username on $selected_fs:\n\n$formatted_quota"
}

# Function to enable quota on a filesystem
enable_filesystem_quota() {
  log "Enable filesystem quota started"
  
  # List mounted filesystems
  local mounted_fs=$(mount | grep "type ext" | awk '{print $3 " " $1}')
  
  if [ -z "$mounted_fs" ]; then
    dialog_info "No Suitable Filesystems" "No suitable filesystems found (only ext2/3/4 are supported)."
    log "No suitable filesystems found for quota"
    return
  fi
  
  # Build options with filesystems
  local fs_options=()
  while read -r line; do
    local mountpoint=$(echo "$line" | awk '{print $1}')
    local device=$(echo "$line" | awk '{print $2}')
    fs_options+=("$mountpoint" "Device: $device")
  done <<< "$mounted_fs"
  
  # Let user choose a filesystem
  local selected_fs=$(dialog_menu "Select Filesystem" "Choose a filesystem to enable quota on:" "${fs_options[@]}")
  
  if [ -z "$selected_fs" ]; then
    log "Filesystem selection cancelled"
    return
  fi
  
  # Determine device
  local selected_device=$(mount | grep " $selected_fs " | awk '{print $1}')
  
  # Check if quota is already enabled in fstab
  if grep -q "^$selected_device.*quota" /etc/fstab; then
    dialog_info "Quota Already Enabled" "Quota is already enabled for $selected_fs in /etc/fstab."
    log "Quota is already enabled for $selected_fs"
    return
  fi
  
  # Ask for quota types
  local quota_type=$(dialog_menu "Quota Type" "What type of quota do you want to enable?" \
    "usrquota" "User quota" \
    "grpquota" "Group quota" \
    "both" "Both")
  
  if [ -z "$quota_type" ]; then
    log "Quota type selection cancelled"
    return
  fi
  
  local quota_options=""
  case $quota_type in
    usrquota) quota_options="usrquota" ;;
    grpquota) quota_options="grpquota" ;;
    both) quota_options="usrquota,grpquota" ;;
  esac
  
  # Backup fstab
  cp /etc/fstab "$BACKUP_DIR/system_state/fstab.backup.$(date +%Y%m%d%H%M%S)"
  
  # Update fstab
  local current_options=$(grep "^$selected_device" /etc/fstab | awk '{print $4}')
  local new_options="${current_options},${quota_options}"
  
  # Replace comma at beginning if current options are "defaults"
  if [ "$current_options" = "defaults" ]; then
    new_options="defaults,${quota_options}"
  fi
  
  # Update fstab line
  sed -i "s|^$selected_device.*|$selected_device $selected_fs $(grep "^$selected_device" /etc/fstab | awk '{print $3}') $new_options $(grep "^$selected_device" /etc/fstab | awk '{print $5 " " $6}')|" /etc/fstab
  
  log "Quota options $quota_options added to $selected_fs in fstab"
  
  # Create quota files
  if [[ $quota_options == *"usrquota"* ]]; then
    touch $selected_fs/aquota.user
    chmod 600 $selected_fs/aquota.user
  fi
  
  if [[ $quota_options == *"grpquota"* ]]; then
    touch $selected_fs/aquota.group
    chmod 600 $selected_fs/aquota.group
  fi
  
  # Ask about remounting the filesystem
  if dialog_confirm "Remount" "The filesystem needs to be remounted to apply the changes. Do you want to do this now?"; then
    # Remount
    mount -o remount $selected_fs
    
    # Check quota files and initialize
    if [ $? -eq 0 ]; then
      dialog_info "Quota Check" "Quota check is being performed on $selected_fs. This may take a while, depending on the filesystem size."
      
      # Set quotacheck for the selected filesystem only
      if [[ $quota_options == *"usrquota"* && $quota_options == *"grpquota"* ]]; then
        quotacheck -vugm $selected_fs
      elif [[ $quota_options == *"usrquota"* ]]; then
        quotacheck -vum $selected_fs
      elif [[ $quota_options == *"grpquota"* ]]; then
        quotacheck -vgm $selected_fs
      fi
      
      # Enable quota
      quotaon $selected_fs
      
      log "Quota initialized and enabled on $selected_fs"
      dialog_info "Quota Enabled" "Quota has been successfully enabled on $selected_fs."
    else
      log "Failed to remount $selected_fs"
      dialog_info "Remount Failed" "Failed to remount $selected_fs. Quota is configured in fstab but not active. Restart the system to apply the changes."
    fi
  else
    log "User chose not to remount $selected_fs"
    dialog_info "Quota Configured" "Quota is configured in fstab but not active. Restart the system or remount the filesystem to apply the changes."
  fi
}

# Function for managing user groups
manage_user_groups() {
  local username="$1"
  log "Group management started for user: $username"
  
  # List of all groups on the system
  mapfile -t all_groups < <(cut -d: -f1 /etc/group | sort)
  
  # Current groups of the user
  mapfile -t user_groups < <(groups "$username" | sed 's/.*: //' | tr ' ' '\n')
  
  # Build checkbox list with all groups
  local group_options=()
  for group in "${all_groups[@]}"; do
    local is_member=0
    for user_group in "${user_groups[@]}"; do
      if [ "$group" == "$user_group" ]; then
        is_member=1
        break
      fi
    done
    
    if [ $is_member -eq 1 ]; then
      group_options+=("$group" "Group" "on")
    else
      group_options+=("$group" "Group" "off")
    fi
  done
  
  # Show dialog for group selection
  local selected_groups=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Groups for $username" \
    --checklist "Select the groups for $username:" 20 60 15 "${group_options[@]}" 3>&1 1>&2 2>&3)
  
  # Check if groups were selected
  if [ $? -ne 0 ]; then
    log "Group selection cancelled"
    return
  fi
  
  # Backup current group membership
  mkdir -p "$BACKUP_DIR/users"
  groups "$username" > "$BACKUP_DIR/users/${username}_groups_before.txt"
  
  # Update user groups
  local primary_group=$(id -gn "$username")
  # First, reset the users supplementary groups (keeping primary group)
  usermod -G "" "$username" 2>/dev/null
  
  # Then add to the selected groups
  for group in $selected_groups; do
    # Skip the primary group as it's handled separately
    if [ "$group" != "$primary_group" ]; then
      usermod -a -G "$group" "$username"
      log "User $username added to group $group"
    fi
  done
  
  # Record new groups
  groups "$username" > "$BACKUP_DIR/users/${username}_groups_after.txt"
  
  dialog_info "Groups Updated" "The group memberships for $username have been updated.\n\nNew groups: $(groups "$username" | sed 's/.*: //')"
}

# Function for managing sudo access
manage_sudo_access() {
  local username="$1"
  log "Sudo rights management started for user: $username"
  
  # Check current sudo status
  local has_sudo=0
  if groups "$username" | grep -q "\<sudo\>"; then
    has_sudo=1
  elif [ -f "/etc/sudoers.d/$username" ]; then
    has_sudo=1
  elif grep -q "^$username" /etc/sudoers; then
    has_sudo=1
  fi
  
  # Ask if user should have sudo rights
  local sudo_choice="no"
  if [ $has_sudo -eq 1 ]; then
    sudo_choice="yes"
  fi
  
  local new_sudo=$(dialog_menu "Sudo Rights" "Should $username have sudo rights?" \
    "yes" "Yes, grant sudo rights" \
    "no" "No, remove sudo rights" \
    "custom" "Set custom sudo permissions")
  
  if [ -z "$new_sudo" ]; then
    log "Sudo rights selection cancelled"
    return
  fi
  
  # Backup sudoers file
  cp /etc/sudoers "$BACKUP_DIR/system_state/sudoers.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
  if [ -f "/etc/sudoers.d/$username" ]; then
    mkdir -p "$BACKUP_DIR/system_state/sudoers.d"
    cp "/etc/sudoers.d/$username" "$BACKUP_DIR/system_state/sudoers.d/${username}.backup.$(date +%Y%m%d%H%M%S)"
  fi
  
  if [ "$new_sudo" = "yes" ]; then
    # Add user to sudo group
    if ! groups "$username" | grep -q "\<sudo\>"; then
      usermod -a -G sudo "$username"
      log "User $username added to sudo group"
    fi
    dialog_info "Sudo Rights" "Sudo rights have been enabled for $username by adding to the sudo group."
  elif [ "$new_sudo" = "no" ]; then
    # Remove user from sudo group
    if groups "$username" | grep -q "\<sudo\>"; then
      gpasswd -d "$username" sudo 2>/dev/null
      log "User $username removed from sudo group"
    fi
    
    # Remove any personal sudoers files
    if [ -f "/etc/sudoers.d/$username" ]; then
      rm -f "/etc/sudoers.d/$username"
      log "Sudoers file /etc/sudoers.d/$username removed"
    fi
    
    dialog_info "Sudo Rights" "Sudo rights have been disabled for $username."
  elif [ "$new_sudo" = "custom" ]; then
    # Set custom sudo permissions
    
    # First, show dialog with explanation
    dialog_info "Custom Sudo" "Custom sudo configuration allows you to specify exactly what commands the user can run with sudo.\n\nExamples:\n1. Allow all commands without password:\n   $username ALL=(ALL) NOPASSWD: ALL\n\n2. Allow specific commands:\n   $username ALL=(ALL) /bin/ls, /usr/bin/apt"
    
    # Ask for custom sudo line
    local sudo_line=$(dialog_input "Custom Sudo" "Enter the custom sudo line for $username:" "$username ALL=(ALL) ALL")
    
    if [ -z "$sudo_line" ]; then
      log "Custom sudo line input cancelled"
      return
    fi
    
    # Create sudoers.d directory if it doesn't exist
    mkdir -p /etc/sudoers.d
    
    # Write the custom sudo line
    echo "$sudo_line" > "/etc/sudoers.d/$username"
    chmod 440 "/etc/sudoers.d/$username"
    
    log "Custom sudo line added for $username: $sudo_line"
    dialog_info "Custom Sudo" "Custom sudo permissions have been set for $username:\n\n$sudo_line"
  fi
}

# Function for account/password expiry
manage_account_expiry() {
  local username="$1"
  log "Account expiry management started for: $username"
  
  # Get current information
  local current_account_expiry=$(chage -l "$username" | grep "Account expires" | cut -d: -f2- | xargs)
  local current_passwd_expiry=$(chage -l "$username" | grep "Password expires" | cut -d: -f2- | xargs)
  
  if [ "$current_account_expiry" = "never" ]; then
    current_account_expiry="never"
  fi
  
  if [ "$current_passwd_expiry" = "never" ]; then
    current_passwd_expiry="never"
  fi
  
  # Format the current expiry info
  local expiry_info='{
    "Current Expiry Settings": [
      {"Setting": "Account Expiry", "Value": "'$current_account_expiry'"},
      {"Setting": "Password Expiry", "Value": "'$current_passwd_expiry'"}
    ]
  }'
  
  # Format expiry info table
  local formatted_expiry=$(python3 -c "
import json
from tabulate import tabulate
data = json.loads('$expiry_info')
print(tabulate(data['Current Expiry Settings'], headers='keys', tablefmt='grid'))
")
  
  # Show current expiry information
  dialog_info "Current Expiry Settings" "$formatted_expiry"
  
  # Menu for expiry management
  local action=$(dialog_menu "Expiry Management" "Choose an option for $username:" \
    "account" "Set account expiry date (current: $current_account_expiry)" \
    "password" "Set password expiry date (current: $current_passwd_expiry)" \
    "back" "Back to user management")
  
  case $action in
    account)
      local expiry_option=$(dialog_menu "Account Expiry" "Choose an option for account expiry:" \
        "never" "Never (account never expires)" \
        "date" "Specific date (YYYY-MM-DD)" \
        "days" "Number of days from now")
      
      case $expiry_option in
        never)
          chage -E -1 "$username"
          log "Account expiry date for $username set to: never"
          dialog_info "Account Expiry" "Account for $username will never expire."
          ;;
        date)
          local expiry_date=$(dialog_input "Expiry Date" "Enter the expiry date (YYYY-MM-DD):" "")
          if [ -n "$expiry_date" ]; then
            # Validate date format
            if ! date -d "$expiry_date" &> /dev/null; then
              dialog_info "Invalid Date" "Invalid date format. Please use YYYY-MM-DD format."
              log "Invalid date format entered for $username: $expiry_date"
              return
            fi
            
            chage -E "$expiry_date" "$username"
            log "Account expiry date for $username set to: $expiry_date"
            dialog_info "Account Expiry" "Account for $username will expire on: $expiry_date"
          fi
          ;;
        days)
          local days=$(dialog_input "Days Until Expiry" "Enter the number of days until the account expires:" "90")
          if [ -n "$days" ]; then
            # Validate number
            if ! [[ "$days" =~ ^[0-9]+$ ]]; then
              dialog_info "Invalid Input" "Please enter a valid number."
              log "Invalid number of days entered for $username: $days"
              return
            fi
            
            local expiry_date=$(date -d "+$days days" +%Y-%m-%d)
            chage -E "$expiry_date" "$username"
            log "Account expiry date for $username set to: $expiry_date (in $days days)"
            dialog_info "Account Expiry" "Account for $username will expire on: $expiry_date (in $days days)"
          fi
          ;;
      esac
      ;;
    password)
      local expiry_option=$(dialog_menu "Password Expiry" "Choose an option for password expiry:" \
        "never" "Never (password never expires)" \
        "days" "Maximum age in days" \
        "force" "Force password change at next login")
      
      case $expiry_option in
        never)
          chage -M -1 "$username"
          log "Password expiry for $username set to: never"
          dialog_info "Password Expiry" "Password for $username will never expire."
          ;;
        days)
          local max_days=$(dialog_input "Maximum Password Age" "Enter the number of days a password remains valid:" "90")
          if [ -n "$max_days" ]; then
            # Validate number
            if ! [[ "$max_days" =~ ^[0-9]+$ ]]; then
              dialog_info "Invalid Input" "Please enter a valid number."
              log "Invalid number of days entered for $username: $max_days"
              return
            fi
            
            chage -M "$max_days" "$username"
            log "Password maximum age for $username set to: $max_days days"
            dialog_info "Password Expiry" "Password for $username must be changed every $max_days days."
          fi
          ;;
        force)
          chage -d 0 "$username"
          log "Password change forced for $username at next login"
          dialog_info "Password Change" "User $username must change password at next login."
          ;;
      esac
      ;;
    back|*)
      return
      ;;
  esac
}

# Function for creating new users
create_user() {
  log "Create user started"
  
  # Ask for username
  local username=$(dialog_input "Username" "Enter the username for the new user:" "")
  
  if [ -z "$username" ]; then
    log "Username input cancelled"
    return
  fi
  
  # Check if username already exists
  if id "$username" &>/dev/null; then
    dialog_info "Username Exists" "The username '$username' already exists. Please choose a different username."
    log "Username $username already exists"
    return
  fi
  
  # Validate username format
  if ! [[ "$username" =~ ^[a-z][-a-z0-9_]*$ ]]; then
    dialog_info "Invalid Username" "The username must start with a lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores."
    log "Invalid username format: $username"
    return
  fi
  
  # Ask for full name
  local fullname=$(dialog_input "Full Name" "Enter the full name for the user:" "")
  
  # Ask for password
  local password1=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Password" --insecure --passwordbox "Enter the password for $username:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    log "Password input cancelled"
    return
  fi
  
  # Ask for password confirmation
  local password2=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Confirm Password" --insecure --passwordbox "Enter the password again:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    log "Password confirmation cancelled"
    return
  fi
  
  # Check if passwords match
  if [ "$password1" != "$password2" ]; then
    dialog_info "Password Mismatch" "The passwords do not match. Please try again."
    log "Passwords do not match for new user $username"
    return
  fi
  
  # Ask if user should be an administrator
  local is_admin=$(dialog_confirm "Administrator" "Should $username be an administrator (have sudo rights)?")
  local admin_flag=""
  if [ $is_admin -eq 0 ]; then
    admin_flag="--groups sudo"
  fi
  
  # Ask for home directory creation
  local create_home=$(dialog_confirm "Home Directory" "Create a home directory for $username?")
  local home_flag="--create-home"
  if [ $create_home -ne 0 ]; then
    home_flag="--no-create-home"
  fi
  
  # Create the user
  if [ -z "$fullname" ]; then
    useradd $home_flag $admin_flag "$username"
  else
    useradd $home_flag $admin_flag --comment "$fullname" "$username"
  fi
  
  # Set the password
  echo "$username:$password1" | chpasswd
  
  log "User $username created"
  
  # Record user creation
  mkdir -p "$BACKUP_DIR/users"
  echo "User $username created on $(date)" >> "$BACKUP_DIR/users/user_creation.log"
  
  # Ask if password should be changed at first login
  if dialog_confirm "Password Change" "Should $username be required to change password at first login?"; then
    chage -d 0 "$username"
    log "Password change required at first login for $username"
  fi
  
  dialog_info "User Created" "User $username has been created successfully.\n\nFull name: $fullname\nAdmin: $([ $is_admin -eq 0 ] && echo "Yes" || echo "No")\nHome directory: $([ $create_home -eq 0 ] && echo "Yes" || echo "No")"
}

# Function for deleting users
delete_user() {
  log "Delete user started"
  
  # Build options with users
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    dialog_info "Delete User" "No normal users found on the system."
    log "No normal users found"
    return
  fi
  
  # Build menu options with users
  local options=()
  for ((i=0; i<${#user_list[@]}; i++)); do
    local user=${user_list[$i]}
    local uid=$(id -u "$user")
    local home=$(eval echo ~$user)
    options+=("$user" "UID: $uid, Home: $home")
  done
  
  # Let user choose
  local selected_user=$(dialog_menu "Select User" "Choose a user to delete:" "${options[@]}")
  
  if [ -z "$selected_user" ]; then
    log "User selection for deletion cancelled"
    return
  fi
  
  # Ask for confirmation
  if ! dialog_confirm "Delete User" "Are you sure you want to delete the user '$selected_user'?\n\nThis action cannot be undone."; then
    log "User deletion cancelled for $selected_user"
    return
  fi
  
  # Ask about home directory
  local home_dir=$(eval echo ~$selected_user)
  local remove_home=0
  if [ -d "$home_dir" ]; then
    if dialog_confirm "Remove Home Directory" "Do you want to remove the home directory '$home_dir'?"; then
      remove_home=1
    fi
  fi
  
  # Backup user information before deletion
  mkdir -p "$BACKUP_DIR/users"
  id "$selected_user" > "$BACKUP_DIR/users/${selected_user}_id.txt"
  groups "$selected_user" > "$BACKUP_DIR/users/${selected_user}_groups.txt"
  chage -l "$selected_user" > "$BACKUP_DIR/users/${selected_user}_chage.txt"
  
  # Delete the user
  if [ $remove_home -eq 1 ]; then
    userdel -r "$selected_user"
    log "User $selected_user deleted with home directory"
  else
    userdel "$selected_user"
    log "User $selected_user deleted without removing home directory"
  fi
  
  # Record user deletion
  echo "User $selected_user deleted on $(date)" >> "$BACKUP_DIR/users/user_deletion.log"
  
  dialog_info "User Deleted" "User $selected_user has been deleted.\n\nHome directory removed: $([ $remove_home -eq 1 ] && echo "Yes" || echo "No")"
}

# Function for group management
manage_groups() {
  log "Group management started"
  
  # List all groups
  mapfile -t all_groups < <(cut -d: -f1 /etc/group | sort)
  
  # Build menu options with groups
  local options=("new" "Create new group")
  for group in "${all_groups[@]}"; do
    options+=("$group" "Manage group")
  done
  
  # Let user choose
  local selection=$(dialog_menu "Group Management" "Choose a group to manage or create a new group:" "${options[@]}")
  
  if [ -z "$selection" ]; then
    log "Group selection cancelled"
    return
  fi
  
  if [ "$selection" = "new" ]; then
    # Create new group
    local new_group=$(dialog_input "New Group" "Enter the name for the new group:" "")
    
    if [ -z "$new_group" ]; then
      log "New group creation cancelled"
      return
    fi
    
    # Check if group already exists
    if getent group "$new_group" >/dev/null; then
      dialog_info "Group Exists" "The group '$new_group' already exists. Choose a different name."
      log "Attempt to create existing group: $new_group"
      return
    fi
    
    # Create new group
    groupadd "$new_group"
    log "New group created: $new_group"
    dialog_info "Group Created" "The group '$new_group' has been successfully created."
    
    # Ask about adding members
    if dialog_confirm "Add Members" "Do you want to add members to the new group '$new_group'?"; then
      manage_group_members "$new_group"
    fi
  else
    # Manage existing group
    local group="$selection"
    local group_id=$(getent group "$group" | cut -d: -f3)
    
    # Show group information
    local group_members=$(getent group "$group" | cut -d: -f4 | tr ',' ' ')
    local member_count=$(echo "$group_members" | wc -w)
    
    # Format group information in table
    local group_info='{
      "Group Information": [
        {"Property": "Group Name", "Value": "'$group'"},
        {"Property": "Group ID", "Value": "'$group_id'"},
        {"Property": "Member Count", "Value": "'$member_count'"}
      ]
    }'
    
    if [ -n "$group_members" ]; then
      # Format the members as a comma-separated list
      local formatted_members=$(echo "$group_members" | tr ' ' ', ' | sed 's/,$//')
      group_info=$(echo "$group_info" | sed 's/\]$/,{"Property": "Members", "Value": "'"$formatted_members"'"}\]/')
    else
      group_info=$(echo "$group_info" | sed 's/\]$/,{"Property": "Members", "Value": "None"}\]/')
    fi
    
    # Format group info table
    local formatted_info=$(python3 -c "
import json
from tabulate import tabulate
data = json.loads('$group_info')
print(tabulate(data['Group Information'], headers='keys', tablefmt='grid'))
")
    
    dialog_info "Group: $group" "$formatted_info"
    
    # Options for group management
    local action=$(dialog_menu "Group Management - $group" "Choose an action for group '$group':" \
      "members" "Manage members" \
      "rename" "Rename group" \
      "gid" "Change GID" \
      "delete" "Delete group" \
      "back" "Back to group management")
    
    case $action in
      members)
        manage_group_members "$group"
        ;;
      rename)
        local new_name=$(dialog_input "Rename Group" "Enter the new name for group '$group':" "$group")
        
        if [ -z "$new_name" ] || [ "$new_name" = "$group" ]; then
          log "Group rename cancelled or same name used"
          return
        fi
        
        # Check if new name already exists
        if getent group "$new_name" >/dev/null; then
          dialog_info "Group Exists" "The group '$new_name' already exists. Choose a different name."
          log "Attempt to rename group to existing group: $new_name"
          return
        fi
        
        # Backup before renaming
        mkdir -p "$BACKUP_DIR/users"
        getent group "$group" > "$BACKUP_DIR/users/group_${group}_before_rename.txt"
        
        # Rename group
        groupmod -n "$new_name" "$group"
        log "Group renamed from '$group' to '$new_name'"
        dialog_info "Group Renamed" "The group has been renamed from '$group' to '$new_name'."
        ;;
      gid)
        local current_gid=$(getent group "$group" | cut -d: -f3)
        local new_gid=$(dialog_input "Change GID" "Enter the new GID for group '$group':\nCurrent GID: $current_gid" "$current_gid")
        
        if [ -z "$new_gid" ] || [ "$new_gid" = "$current_gid" ]; then
          log "GID change cancelled or same GID used"
          return
        fi
        
        # Validate GID format
        if ! [[ "$new_gid" =~ ^[0-9]+$ ]]; then
          dialog_info "Invalid GID" "The GID must be a number."
          log "Invalid GID format: $new_gid"
          return
        fi
        
        # Check if GID is already in use
        if getent group "$new_gid" >/dev/null; then
          dialog_info "GID In Use" "The GID $new_gid is already in use. Choose a different GID."
          log "Attempt to use existing GID: $new_gid"
          return
        fi
        
        # Backup before changing GID
        mkdir -p "$BACKUP_DIR/users"
        getent group "$group" > "$BACKUP_DIR/users/group_${group}_before_gid_change.txt"
        
        # Change GID
        groupmod -g "$new_gid" "$group"
        log "GID for group '$group' changed from $current_gid to $new_gid"
        dialog_info "GID Changed" "The GID for group '$group' has been changed from $current_gid to $new_gid."
        ;;
      delete)
        if dialog_confirm "Delete Group" "Are you sure you want to delete the group '$group'?\n\nWarning: This can affect files and user permissions."; then
          # Backup before deletion
          mkdir -p "$BACKUP_DIR/users"
          getent group "$group" > "$BACKUP_DIR/users/group_${group}_before_deletion.txt"
          
          groupdel "$group"
          log "Group deleted: $group"
          dialog_info "Group Deleted" "The group '$group' has been successfully deleted."
        else
          log "Group deletion cancelled: $group"
        fi
        ;;
      back|*)
        return
        ;;
    esac
  fi
}

# Function for managing group members
manage_group_members() {
  local group="$1"
  log "Member management started for group: $group"
  
  # Get current members
  local current_members=$(getent group "$group" | cut -d: -f4)
  mapfile -t member_list < <(echo "$current_members" | tr ',' '\n')
  
  # Get all non-system users
  mapfile -t all_users < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | sort)
  
  # Build checkbox list with all users
  local user_options=()
  for user in "${all_users[@]}"; do
    local is_member=0
    for member in "${member_list[@]}"; do
      if [ "$user" = "$member" ]; then
        is_member=1
        break
      fi
    done
    
    if [ $is_member -eq 1 ]; then
      user_options+=("$user" "User" "on")
    else
      user_options+=("$user" "User" "off")
    fi
  done
  
  # Show dialog for member selection
  local selected_users=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Members for group $group" \
    --checklist "Select the members for group '$group':" 20 60 15 "${user_options[@]}" 3>&1 1>&2 2>&3)
  
  # Check if members were selected
  if [ $? -ne 0 ]; then
    log "Member selection cancelled"
    return
  fi
  
  # Backup current membership
  mkdir -p "$BACKUP_DIR/users"
  getent group "$group" > "$BACKUP_DIR/users/group_${group}_members_before.txt"
  
  # Clear current group membership
  gpasswd -M "" "$group" 2>/dev/null
  
  # Add selected users to group
  if [ -n "$selected_users" ]; then
    # Replace spaces with commas for gpasswd
    local formatted_users=$(echo "$selected_users" | tr ' ' ',')
    gpasswd -M "$formatted_users" "$group" 2>/dev/null
    log "Group members updated for $group: $formatted_users"
  fi
  
  # Record new membership
  getent group "$group" > "$BACKUP_DIR/users/group_${group}_members_after.txt"
  
  dialog_info "Members Updated" "The member list for group '$group' has been updated."
}

# Function for user security audit
audit_user_accounts() {
  log "User accounts audit started"
  
  local audit_log="$LOG_DIR/user_audit_$(date +%Y%m%d%H%M%S).log"
  
  (
    echo "10"; echo "XXX"; echo "Auditing user accounts..."; echo "XXX"
    
    # Begin audit log file
    echo "===== USER ACCOUNTS AUDIT =====" > "$audit_log"
    echo "Date: $(date)" >> "$audit_log"
    echo "System: $(hostname)" >> "$audit_log"
    echo "===============================" >> "$audit_log"
    echo >> "$audit_log"
    
    echo "20"; echo "XXX"; echo "Checking for accounts without password..."; echo "XXX"
    # Check accounts without password
    echo "=== ACCOUNTS WITHOUT PASSWORD ===" >> "$audit_log"
    awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow >> "$audit_log"
    echo >> "$audit_log"
    
    echo "30"; echo "XXX"; echo "Checking for accounts with sudo rights..."; echo "XXX"
    # Check accounts with sudo rights
    echo "=== ACCOUNTS WITH SUDO RIGHTS ===" >> "$audit_log"
    grep -Po '^sudo:.*:\K.*$' /etc/group | tr ',' '\n' >> "$audit_log"
    echo >> "$audit_log"
    
    echo "40"; echo "XXX"; echo "Checking for UID 0 accounts..."; echo "XXX"
    # Check accounts with UID 0 (root privileges)
    echo "=== ACCOUNTS WITH UID 0 (ROOT RIGHTS) ===" >> "$audit_log"
    awk -F: '($3 == 0) {print $1}' /etc/passwd >> "$audit_log"
    echo >> "$audit_log"
    
    echo "50"; echo "XXX"; echo "Checking for users with shell access..."; echo "XXX"
    # Check users with shell access
    echo "=== ACCOUNTS WITH SHELL ACCESS ===" >> "$audit_log"
    grep -v '/nologin\|/false' /etc/passwd | cut -d: -f1,7 >> "$audit_log"
    echo >> "$audit_log"
    
    echo "60"; echo "XXX"; echo "Checking for inactive accounts..."; echo "XXX"
    # Check for inactive accounts (login history)
    echo "=== INACTIVE ACCOUNTS (NO LOGIN IN 90 DAYS) ===" >> "$audit_log"
    lastlog -b 90 | grep -v "Never" >> "$audit_log"
    echo >> "$audit_log"
    
    echo "70"; echo "XXX"; echo "Checking for locked accounts..."; echo "XXX"
    # Check locked accounts
    echo "=== LOCKED ACCOUNTS ===" >> "$audit_log"
    awk -F: '($2 ~ /^!/) {print $1}' /etc/shadow >> "$audit_log"
    echo >> "$audit_log"
    
    echo "80"; echo "XXX"; echo "Checking for password expiry dates..."; echo "XXX"
    # Check password expiry dates
    echo "=== PASSWORD EXPIRY DATES ===" >> "$audit_log"
    for user in $(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd); do
      echo "User: $user" >> "$audit_log"
      chage -l "$user" | grep "Password expires" >> "$audit_log"
      echo >> "$audit_log"
    done
    
    echo "90"; echo "XXX"; echo "Checking for suspicious activity..."; echo "XXX"
    # Check for suspicious activity (failed login attempts)
    echo "=== FAILED LOGIN ATTEMPTS (LAST 10) ===" >> "$audit_log"
    if [ -f /var/log/auth.log ]; then
      grep "Failed password" /var/log/auth.log | tail -10 >> "$audit_log"
    fi
    echo >> "$audit_log"
    
    echo "100"; echo "XXX"; echo "Audit completed."; echo "XXX"
    
    # Summary
    echo "===== AUDIT SUMMARY =====" >> "$audit_log"
    echo "Total users: $(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | wc -l)" >> "$audit_log"
    echo "Users with sudo rights: $(grep -Po '^sudo:.*:\K.*' /etc/group | tr ',' '\n' | wc -l)" >> "$audit_log"
    echo "Accounts without password: $(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow | wc -l)" >> "$audit_log"
    echo "Locked accounts: $(awk -F: '($2 ~ /^!/) {print $1}' /etc/shadow | wc -l)" >> "$audit_log"
    echo "===============================" >> "$audit_log"
    
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "User Accounts Audit" --gauge "Performing security audit..." 10 70 0
  
  # Create formatted audit summary for display
  local audit_summary=$(grep -A 5 "AUDIT SUMMARY" "$audit_log")
  
  # Format the security findings as tables for better readability
  local password_issues=$(grep -A 2 "WITHOUT PASSWORD" "$audit_log" | tail -n +2)
  local sudo_users=$(grep -A 10 "WITH SUDO RIGHTS" "$audit_log" | tail -n +2 | grep -v "^$" | grep -v "===" | sort)
  local locked_accounts=$(grep -A 10 "LOCKED ACCOUNTS" "$audit_log" | tail -n +2 | grep -v "^$" | grep -v "===" | sort)
  
  # Format the output for dialog display with better tables
  local formatted_output="══════════════ SECURITY AUDIT SUMMARY ══════════════\n\n"
  
  formatted_output+="$audit_summary\n\n"
  
  formatted_output+="═════════════ SECURITY FINDINGS ═════════════\n\n"
  
  # Format the sudo users list
  if [ ! -z "$sudo_users" ]; then
    formatted_output+="USERS WITH SUDO RIGHTS:\n"
    formatted_output+="┌────────────────────┐\n"
    while IFS= read -r user; do
      formatted_output+="│ $user$(printf '%*s' $((20 - ${#user})) '')│\n"
    done <<< "$sudo_users"
    formatted_output+="└────────────────────┘\n\n"
  else
    formatted_output+="USERS WITH SUDO RIGHTS: None\n\n"
  fi
  
  # Format accounts without password
  if [ ! -z "$password_issues" ]; then
    formatted_output+="ACCOUNTS WITHOUT PASSWORD:\n"
    formatted_output+="┌────────────────────┐\n"
    while IFS= read -r user; do
      if [ ! -z "$user" ]; then
        formatted_output+="│ $user$(printf '%*s' $((20 - ${#user})) '')│\n"
      fi
    done <<< "$password_issues"
    formatted_output+="└────────────────────┘\n\n"
  else
    formatted_output+="ACCOUNTS WITHOUT PASSWORD: None\n\n"
  fi
  
  # Format locked accounts
  if [ ! -z "$locked_accounts" ]; then
    formatted_output+="LOCKED ACCOUNTS:\n"
    formatted_output+="┌────────────────────┐\n"
    while IFS= read -r user; do
      if [ ! -z "$user" ]; then
        formatted_output+="│ $user$(printf '%*s' $((20 - ${#user})) '')│\n"
      fi
    done <<< "$locked_accounts"
    formatted_output+="└────────────────────┘\n\n"
  else
    formatted_output+="LOCKED ACCOUNTS: None\n\n"
  fi
  
  formatted_output+="Full audit results saved to: $audit_log"
  
  # Create a backup of the audit
  cp "$audit_log" "$BACKUP_DIR/users/audit_$(date +%Y%m%d%H%M%S).log"
  
  log "User accounts audit completed and saved to $audit_log"
  dialog_info "Audit Results" "$formatted_output"
}

# Function for advanced user search
advanced_user_search() {
  log "Advanced user search started"
  
  # Ask for search type
  local search_type=$(dialog_menu "Search Type" "What kind of search do you want to perform?" \
    "login" "Search by last login time" \
    "shell" "Search by login shell" \
    "uid" "Search by UID range" \
    "group" "Search by group membership" \
    "pattern" "Search by username pattern" \
    "back" "Back to user management")
  
  if [ -z "$search_type" ] || [ "$search_type" = "back" ]; then
    log "Advanced user search cancelled"
    return
  fi
  
  local search_results=""
  
  case $search_type in
    login)
      local login_time=$(dialog_menu "Last Login" "Find users based on last login time:" \
        "never" "Users who have never logged in" \
        "recent" "Users who logged in recently (last 7 days)" \
        "inactive" "Users inactive for a specific period" \
        "back" "Back to search options")
      
      if [ -z "$login_time" ] || [ "$login_time" = "back" ]; then
        log "Login time search cancelled"
        return
      fi
      
      case $login_time in
        never)
          search_results=$(lastlog | grep "Never logged in" | awk '{print $1}')
          ;;
        recent)
          search_results=$(last -s -7days | awk '{print $1}' | sort -u)
          ;;
        inactive)
          local days=$(dialog_input "Inactive Period" "Enter the number of days of inactivity:" "30")
          if [ -z "$days" ]; then
            log "Inactive period input cancelled"
            return
          fi
          search_results=$(lastlog -b $days | grep -v "Never\|Username" | awk '{print $1}')
          ;;
      esac
      ;;
    shell)
      local available_shells=()
      while IFS= read -r shell; do
        available_shells+=("$shell" "")
      done < /etc/shells
      
      # Build shell options
      local shell_options=()
      for shell in "${available_shells[@]}"; do
        if [ -n "$shell" ] && [ "$shell" != "" ]; then
          shell_options+=("$shell" "Shell")
        fi
      done
      
      # Let user choose a shell
      local selected_shell=$(dialog_menu "Select Shell" "Choose a shell to search for users:" "${shell_options[@]}")
      
      if [ -z "$selected_shell" ]; then
        log "Shell selection cancelled"
        return
      fi
      
      search_results=$(grep "$selected_shell$" /etc/passwd | cut -d: -f1)
      ;;
    uid)
      local min_uid=$(dialog_input "Minimum UID" "Enter the minimum UID (≥ 1000 for normal users):" "1000")
      if [ -z "$min_uid" ]; then
        log "Minimum UID input cancelled"
        return
      fi
      
      local max_uid=$(dialog_input "Maximum UID" "Enter the maximum UID:" "60000")
      if [ -z "$max_uid" ]; then
        log "Maximum UID input cancelled"
        return
      fi
      
      search_results=$(awk -F: -v min="$min_uid" -v max="$max_uid" '($3 >= min && $3 <= max) {print $1}' /etc/passwd)
      ;;
    group)
      # List all groups
      mapfile -t all_groups < <(cut -d: -f1 /etc/group | sort)
      
      # Build group options
      local group_options=()
      for group in "${all_groups[@]}"; do
        group_options+=("$group" "Group")
      done
      
      # Let user choose a group
      local selected_group=$(dialog_menu "Select Group" "Choose a group to find its members:" "${group_options[@]}")
      
      if [ -z "$selected_group" ]; then
        log "Group selection cancelled"
        return
      fi
      
      # Get group members
      local group_members=$(getent group "$selected_group" | cut -d: -f4 | tr ',' ' ')
      
      if [ -z "$group_members" ]; then
        search_results="No members found in group $selected_group"
      else
        search_results=$group_members
      fi
      ;;
    pattern)
      local pattern=$(dialog_input "Username Pattern" "Enter a pattern to search for (e.g., 'admin*' for usernames starting with 'admin'):" "")
      if [ -z "$pattern" ]; then
        log "Pattern input cancelled"
        return
      fi
      
      search_results=$(awk -F: -v pattern="$pattern" 'BEGIN{IGNORECASE=1} $1 ~ pattern {print $1}' /etc/passwd)
      ;;
  esac
  
  # Process and display results
  if [ -z "$search_results" ]; then
    dialog_info "Search Results" "No users found matching your search criteria."
    log "No users found for search type: $search_type"
    return
  fi
  
  # Format the results
  local formatted_results="SEARCH RESULTS:\n\n"
  formatted_results+="┌────────────────────────────────────────┐\n"
  
  # Count the number of results
  local result_count=0
  
  while IFS= read -r user; do
    if [ ! -z "$user" ]; then
      local uid=$(id -u "$user" 2>/dev/null)
      local groups=$(id -Gn "$user" 2>/dev/null | tr ' ' ',' | cut -c 1-25)
      
      if [ ! -z "$uid" ]; then
        formatted_results+="│ $user$(printf '%*s' $((20 - ${#user})) '')│ UID: $uid$(printf '%*s' $((8 - ${#uid})) '')│\n"
        result_count=$((result_count + 1))
      fi
    fi
  done <<< "$search_results"
  
  formatted_results+="└────────────────────────────────────────┘\n"
  formatted_results+="\nTotal results: $result_count"
  
  # Show results
  dialog_info "Search Results" "$formatted_results"
  
  # Ask if user wants to perform an action on one of the results
  if [ $result_count -gt 0 ] && dialog_confirm "User Action" "Do you want to perform an action on one of these users?"; then
    # Build options with found users
    local user_options=()
    while IFS= read -r user; do
      if [ ! -z "$user" ]; then
        local uid=$(id -u "$user" 2>/dev/null)
        if [ ! -z "$uid" ]; then
          user_options+=("$user" "UID: $uid")
        fi
      fi
    done <<< "$search_results"
    
    # Let user choose
    local selected_user=$(dialog_menu "Select User" "Choose a user to manage:" "${user_options[@]}")
    
    if [ -z "$selected_user" ]; then
      log "User selection from search results cancelled"
      return
    fi
    
    # Redirect to user dashboard for the selected user
    user_dashboard "$selected_user"
  fi
}

# Function for user management main menu
user_management() {
  log "User management started"
  
  while true; do
    local action=$(dialog_menu "User Management" "Choose an option:" \
      "dashboard" "User dashboard" \
      "create" "Create a new user" \
      "delete" "Delete a user" \
      "password" "Change password" \
      "groups" "Manage groups" \
      "audit" "Security audit of user accounts" \
      "search" "Advanced user search" \
      "back" "Back to main menu")
    
    case $action in
      dashboard)
        user_dashboard
        ;;
      create)
        create_user
        ;;
      delete)
        delete_user
        ;;
      password)
        change_password
        ;;
      groups)
        manage_groups
        ;;
      audit)
        audit_user_accounts
        ;;
      search)
        advanced_user_search
        ;;
      back|"")
        log "User management exited"
        return
        ;;
    esac
  done
}

#######################################
# NETWORK FUNCTIONS
#######################################

# Function for network configuration
configure_network() {
  log "Network configuration started"
  
  # Ask for confirmation
  if ! dialog_confirm "Network Configuration" "Do you want to proceed with configuring the network?\n\nWarning: Changing network settings may cause you to lose connection to this server if you are connected via SSH."; then
    log "Network configuration cancelled by user"
    return
  fi
  
  # Backup netplan configuration
  log "Backing up existing netplan configurations"
  mkdir -p "$BACKUP_DIR/network/netplan"
  find /etc/netplan -name "*.yaml" -exec cp {} "$BACKUP_DIR/network/netplan/" \; 2>/dev/null
  
  # Detect network interfaces
  log "Detecting network interfaces"
  mapfile -t interface_list < <(ls /sys/class/net | grep -v lo)
  
  if [ ${#interface_list[@]} -eq 0 ]; then
    dialog_info "Network Configuration" "No network interfaces found."
    log "No network interfaces found"
    return
  fi
  
  # Build menu options with interfaces
  local options=()
  for ((i=0; i<${#interface_list[@]}; i++)); do
    # Get interface details
    local interface=${interface_list[$i]}
    local mac=$(cat /sys/class/net/$interface/address 2>/dev/null || echo "Unknown")
    local link_state=$(cat /sys/class/net/$interface/operstate 2>/dev/null || echo "Unknown")
    
    options+=("$i" "${interface_list[$i]} (MAC: $mac, State: $link_state)")
  done

  # Let user choose an interface
  local selected_interface_index=$(dialog_menu "Select Interface" "Choose a network interface to configure:" "${options[@]}")
  
  if [ -z "$selected_interface_index" ]; then
    log "Interface selection cancelled"
    return
  fi
  
  local selected_interface=${interface_list[$selected_interface_index]}
  log "Selected interface: $selected_interface"
  
  # Show configuration options for the selected interface
  local config_action=$(dialog_menu "Configure $selected_interface" "Choose a configuration action:" \
    "static" "Configure static IP address" \
    "dhcp" "Configure DHCP (automatic IP)" \
    "dns" "Configure DNS servers" \
    "wifi" "Configure WiFi settings" \
    "monitor" "Monitor interface bandwidth" \
    "capture" "Capture packets on interface" \
    "back" "Back to network menu")
  
  case $config_action in
    static)
      # Configure static IP
      local ip_address=$(dialog_input "IP Address" "Enter the static IP address for $selected_interface:" "")
      if [ -z "$ip_address" ]; then
        log "Static IP configuration cancelled"
        return
      fi
      
      local subnet_mask=$(dialog_input "Subnet Mask" "Enter the subnet mask (CIDR format, e.g., 24 for 255.255.255.0):" "24")
      local gateway=$(dialog_input "Default Gateway" "Enter the default gateway IP address:" "")
      
      # Create netplan configuration
      mkdir -p /etc/netplan
      
      # Find or create appropriate netplan config file
      local netplan_file="/etc/netplan/01-netcfg.yaml"
      if [ ! -f "$netplan_file" ]; then
        # Create new file
        cat > "$netplan_file" << EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      addresses:
        - $ip_address/$subnet_mask
      gateway4: $gateway
EOL
      else
        # Update existing file
        if grep -q "$selected_interface:" "$netplan_file"; then
          # Interface already in config, need to update
          sed -i "/^ *$selected_interface:/,/^ *[a-z]/ s/^ *addresses:.*/      addresses:\n        - $ip_address\/$subnet_mask/" "$netplan_file"
          sed -i "/^ *$selected_interface:/,/^ *[a-z]/ s/^ *gateway4:.*/      gateway4: $gateway/" "$netplan_file"
        else
          # Need to add interface section
          sed -i "/ethernets:/a\\    $selected_interface:\\n      addresses:\\n        - $ip_address/$subnet_mask\\n      gateway4: $gateway" "$netplan_file"
        fi
      fi
      
      # Apply configuration
      netplan apply
      
      log "Static IP configured for $selected_interface: $ip_address/$subnet_mask"
      dialog_info "Network Configured" "Static IP address has been configured for $selected_interface:\n\nIP: $ip_address/$subnet_mask\nGateway: $gateway\n\nConfiguration has been applied."
      ;;
    
    dhcp)
      # Configure DHCP
      # Create or update netplan configuration
      mkdir -p /etc/netplan
      
      # Find or create appropriate netplan config file
      local netplan_file="/etc/netplan/01-netcfg.yaml"
      if [ ! -f "$netplan_file" ]; then
        # Create new file
        cat > "$netplan_file" << EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      dhcp4: true
EOL
      else
        # Update existing file
        if grep -q "$selected_interface:" "$netplan_file"; then
          # Interface already in config, need to update
          sed -i "/^ *$selected_interface:/,/^ *[a-z]/ s/^ *dhcp4:.*/      dhcp4: true/" "$netplan_file"
          # Remove static IP configuration if it exists
          sed -i "/^ *$selected_interface:/,/^ *[a-z]/ { /^ *addresses:/d }" "$netplan_file"
          sed -i "/^ *$selected_interface:/,/^ *[a-z]/ { /^ *gateway4:/d }" "$netplan_file"
        else
          # Need to add interface section
          sed -i "/ethernets:/a\\    $selected_interface:\\n      dhcp4: true" "$netplan_file"
        fi
      fi
      
      # Apply configuration
      netplan apply
      
      log "DHCP configured for $selected_interface"
      dialog_info "Network Configured" "DHCP has been configured for $selected_interface.\n\nConfiguration has been applied."
      ;;
    
    dns)
      # Configure DNS servers
      local dns_servers=$(dialog_input "DNS Servers" "Enter DNS server IP addresses (space-separated):" "8.8.8.8 8.8.4.4")
      if [ -z "$dns_servers" ]; then
        log "DNS configuration cancelled"
        return
      fi
      
      # Create or update netplan configuration
      mkdir -p /etc/netplan
      
      # Find or create appropriate netplan config file
      local netplan_file="/etc/netplan/01-netcfg.yaml"
      if [ ! -f "$netplan_file" ]; then
        dialog_info "No Netplan File" "No netplan configuration file found. Please configure IP settings first."
        log "No netplan file found for DNS configuration"
        return
      fi
      
      # Update existing file with nameservers
      if grep -q "$selected_interface:" "$netplan_file"; then
        # Format DNS servers for YAML
        local dns_yaml=""
        for server in $dns_servers; do
          dns_yaml+="        - $server\n"
        done
        
        # Remove trailing newline
        dns_yaml=${dns_yaml%\\n}
        
        # Add nameservers configuration
        if grep -q "nameservers:" "$netplan_file"; then
          # Update existing nameservers
          sed -i "/^ *nameservers:/,/^ *[a-z]/ { /^ *addresses:/d }" "$netplan_file"
          sed -i "/^ *nameservers:/a\\      addresses:\\n$dns_yaml" "$netplan_file"
        else
          # Add new nameservers section
          sed -i "/^ *$selected_interface:/a\\      nameservers:\\n        addresses:\\n$dns_yaml" "$netplan_file"
        fi
      else
        dialog_info "Interface Not Found" "Interface $selected_interface not found in netplan configuration."
        log "Interface not found in netplan for DNS configuration"
        return
      fi
      
      # Apply configuration
      netplan apply
      
      log "DNS servers configured for $selected_interface: $dns_servers"
      dialog_info "DNS Configured" "DNS servers have been configured for $selected_interface:\n\n$dns_servers\n\nConfiguration has been applied."
      ;;
    
    wifi)
      # Configure WiFi settings
      # Check if this is a WiFi interface
      if [ ! -d "/sys/class/net/$selected_interface/wireless" ]; then
        dialog_info "Not WiFi" "The selected interface ($selected_interface) is not a WiFi interface."
        log "$selected_interface is not a WiFi interface"
        return
      fi
      
      local ssid=$(dialog_input "WiFi SSID" "Enter the WiFi network name (SSID):" "")
      if [ -z "$ssid" ]; then
        log "WiFi configuration cancelled"
        return
      fi
      
      local password=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "WiFi Password" --insecure --passwordbox "Enter the WiFi password:" 10 60 3>&1 1>&2 2>&3)
      if [ $? -ne 0 ]; then
        log "WiFi password input cancelled"
        return
      fi
      
      # Create or update netplan configuration
      mkdir -p /etc/netplan
      
      # Find or create appropriate netplan config file
      local netplan_file="/etc/netplan/01-netcfg.yaml"
      if [ ! -f "$netplan_file" ]; then
        # Create new file
        cat > "$netplan_file" << EOL
network:
  version: 2
  renderer: networkd
  wifis:
    $selected_interface:
      dhcp4: true
      access-points:
        "$ssid":
          password: "$password"
EOL
      else
        # Check if file already has wifis section
        if grep -q "wifis:" "$netplan_file"; then
          # Update existing wifis section
          if grep -q "$selected_interface:" "$netplan_file"; then
            # Update existing interface
            local line_num=$(grep -n "$selected_interface:" "$netplan_file" | cut -d: -f1)
            local indent=$(sed -n "${line_num}p" "$netplan_file" | awk '{print $1}')
            
            # This is a simplistic approach and may not work for all configurations
            sed -i "/^ *$selected_interface:/,/^ *[a-z]/ { /access-points:/d }" "$netplan_file"
            sed -i "/^ *$selected_interface:/a\\      access-points:\\n        \"$ssid\":\\n          password: \"$password\"" "$netplan_file"
          else
            # Add new interface to wifis section
            sed -i "/wifis:/a\\    $selected_interface:\\n      dhcp4: true\\n      access-points:\\n        \"$ssid\":\\n          password: \"$password\"" "$netplan_file"
          fi
        else
          # Add wifis section
          cat >> "$netplan_file" << EOL
  wifis:
    $selected_interface:
      dhcp4: true
      access-points:
        "$ssid":
          password: "$password"
EOL
        fi
      fi
      
      # Apply configuration
      netplan apply
      
      log "WiFi configured for $selected_interface: SSID=$ssid"
      dialog_info "WiFi Configured" "WiFi has been configured for $selected_interface:\n\nSSID: $ssid\n\nConfiguration has been applied."
      ;;
    
    monitor)
      # Monitor interface bandwidth with iftop
      # Check if iftop is installed
      if ! command -v iftop &> /dev/null; then
        if dialog_confirm "Install iftop" "iftop is not installed. Would you like to install it?"; then
          apt update
          apt install -y iftop
          track_installed_package "iftop"
          log "iftop installed"
        else
          dialog_info "Monitor Interface" "iftop is required for bandwidth monitoring."
          log "iftop installation cancelled"
          return
        fi
      fi
      
      # Exit dialog and run iftop
      clear
      echo -e "${GREEN}Starting bandwidth monitor (iftop) on $selected_interface.${NC}"
      echo -e "${YELLOW}Press 'q' to exit and return to menu.${NC}"
      echo
      
      # Run iftop
      iftop -i "$selected_interface" -P
      
      # Return to dialog
      log "Iftop on $selected_interface completed"
      ;;
    
    capture)
      # Packet capture with tcpdump
      # Check if tcpdump is installed
      if ! command -v tcpdump &> /dev/null; then
        if dialog_confirm "Install Tcpdump" "tcpdump is not installed. Would you like to install it?"; then
          apt update
          apt install -y tcpdump
          track_installed_package "tcpdump"
          log "tcpdump installed"
        else
          dialog_info "Tcpdump" "tcpdump is required for this tool."
          log "tcpdump installation cancelled"
          return
        fi
      fi
      
      # Ask for filter
      local filter=$(dialog_input "Capture Filter" "Enter a capture filter (optional, e.g., 'port 80' or 'host 192.168.1.1'):" "")
      
      # Ask for packet limit
      local packet_limit=$(dialog_input "Packet Limit" "Enter the number of packets to capture (leave empty for unlimited):" "100")
      
      # Build command
      local tcpdump_cmd="tcpdump -i $selected_interface -n"
      
      if [ ! -z "$filter" ]; then
        tcpdump_cmd="$tcpdump_cmd $filter"
      fi
      
      if [ ! -z "$packet_limit" ]; then
        tcpdump_cmd="$tcpdump_cmd -c $packet_limit"
      fi
      
      # Exit dialog and run command
      clear
      echo -e "${GREEN}Starting packet capture (tcpdump) on $selected_interface.${NC}"
      echo -e "${YELLOW}Press Ctrl+C to stop capture and return to menu.${NC}"
      echo
      
      # Run tcpdump
      eval "$tcpdump_cmd"
      
      echo
      echo -e "${YELLOW}Press Enter to continue...${NC}"
      read
      
      # Return to dialog
      log "Tcpdump on $selected_interface completed"
      ;;
    
    back|"")
      log "Interface configuration cancelled"
      return
      ;;
  esac
}

# Function for network configuration main menu
network_management() {
  log "Network management started"
  
  while true; do
    local action=$(dialog_menu "Network Management" "Choose an option:" \
      "configure" "Configure network interfaces" \
      "diagnostics" "Network diagnostics" \
      "bandwidth" "Bandwidth monitoring" \
      "security" "Network security" \
      "tools" "Network tools" \
      "vpn" "VPN configuration" \
      "proxy" "Proxy configuration" \
      "dns" "DNS configuration" \
      "back" "Back to main menu")
    
    case $action in
      configure)
        configure_network
        ;;
      diagnostics)
        network_diagnostics
        ;;
      bandwidth)
        bandwidth_monitoring
        ;;
      security)
        network_security
        ;;
      tools)
        network_tools
        ;;
      vpn)
        configure_vpn
        ;;
      proxy)
        configure_proxy
        ;;
      dns)
        configure_dns
        ;;
      back|"")
        log "Network management exited"
        return
        ;;
    esac
  done
}

# Function for VPN configuration
configure_vpn() {
  log "VPN configuration started"
  
  # Menu for VPN options
  local vpn_option=$(dialog_menu "VPN Configuration" "Choose a VPN type:" \
    "openvpn" "Configure OpenVPN" \
    "wireguard" "Configure WireGuard" \
    "status" "VPN connection status" \
    "back" "Back to network menu")
  
  if [ -z "$vpn_option" ] || [ "$vpn_option" = "back" ]; then
    log "VPN configuration cancelled"
    return
  fi
  
  case $vpn_option in
    openvpn)
      # Configure OpenVPN
      # Check if OpenVPN is installed
      if ! command -v openvpn &> /dev/null; then
        if dialog_confirm "Install OpenVPN" "OpenVPN is not installed. Would you like to install it?"; then
          apt update
          apt install -y openvpn
          track_installed_package "openvpn"
          log "OpenVPN installed"
        else
          dialog_info "OpenVPN" "OpenVPN is required for this configuration."
          log "OpenVPN installation cancelled"
          return
        fi
      fi
      
      # OpenVPN options
      local openvpn_option=$(dialog_menu "OpenVPN Configuration" "Choose an option:" \
        "import" "Import OpenVPN configuration file" \
        "status" "OpenVPN connection status" \
        "start" "Start OpenVPN connection" \
        "stop" "Stop OpenVPN connection" \
        "back" "Back to VPN menu")
      
      if [ -z "$openvpn_option" ] || [ "$openvpn_option" = "back" ]; then
        log "OpenVPN option selection cancelled"
        return
      fi
      
      case $openvpn_option in
        import)
          # Import OpenVPN configuration
          local config_file=$(dialog_input "Configuration File" "Enter the path to the OpenVPN configuration file:" "")
          
          if [ -z "$config_file" ]; then
            log "OpenVPN configuration file path input cancelled"
            return
          fi
          
          # Check if file exists
          if [ ! -f "$config_file" ]; then
            dialog_info "File Not Found" "The specified configuration file was not found."
            log "OpenVPN configuration file not found: $config_file"
            return
          fi
          
          # Create OpenVPN directory if it doesn't exist
          mkdir -p /etc/openvpn/client
          
          # Copy the configuration file
          local config_name=$(basename "$config_file")
          cp "$config_file" "/etc/openvpn/client/$config_name"
          
          # Save a backup
          mkdir -p "$BACKUP_DIR/network/openvpn"
          cp "$config_file" "$BACKUP_DIR/network/openvpn/$config_name.backup.$(date +%Y%m%d%H%M%S)"
          
          log "OpenVPN configuration imported: $config_name"
          
          # Ask if user wants to start the connection
          if dialog_confirm "Start Connection" "Do you want to start the OpenVPN connection now?"; then
            # Start the connection
            systemctl start openvpn-client@$(basename "$config_name" .conf)
            
            log "OpenVPN connection started"
            dialog_info "OpenVPN Started" "OpenVPN connection has been started."
          else
            dialog_info "Import Completed" "OpenVPN configuration has been imported but not started."
          fi
          ;;
        status)
          # Check OpenVPN status
          local status_output=""
          
          if systemctl is-active openvpn >/dev/null 2>&1; then
            status_output="OpenVPN service status: ACTIVE\n\n"
            
            # Check for active connections
            status_output+="ACTIVE CONNECTIONS:\n"
            
            local active_connections=0
            for conn in $(ls -1 /etc/openvpn/client/*.conf 2>/dev/null); do
              conn_name=$(basename "$conn" .conf)
              if systemctl is-active openvpn-client@$conn_name >/dev/null 2>&1; then
                status_output+="- $conn_name (ACTIVE)\n"
                active_connections=$((active_connections + 1))
              else
                status_output+="- $conn_name (INACTIVE)\n"
              fi
            done
            
            if [ $active_connections -eq 0 ]; then
              status_output+="No active OpenVPN connections.\n"
            fi
          else
            status_output="OpenVPN service status: INACTIVE\n\nOpenVPN service is not running."
          fi
          
          dialog_info "OpenVPN Status" "$status_output"
          ;;
        start)
          # Start OpenVPN connection
          local configs=()
          for conf in $(ls -1 /etc/openvpn/client/*.conf 2>/dev/null); do
            configs+=("$(basename "$conf" .conf)" "OpenVPN configuration")
          done
          
          if [ ${#configs[@]} -eq 0 ]; then
            dialog_info "No Configurations" "No OpenVPN configurations found."
            log "No OpenVPN configurations found"
            return
          fi
          
          # Let user choose a configuration
          local selected_config=$(dialog_menu "Select Configuration" "Choose an OpenVPN configuration to start:" "${configs[@]}")
          
          if [ -z "$selected_config" ]; then
            log "OpenVPN configuration selection cancelled"
            return
          fi
          
          # Start the connection
          systemctl start openvpn-client@$selected_config
          
          log "OpenVPN connection started: $selected_config"
          dialog_info "OpenVPN Started" "OpenVPN connection '$selected_config' has been started."
          ;;
        stop)
          # Stop OpenVPN connection
          local active_configs=()
          for conf in $(ls -1 /etc/openvpn/client/*.conf 2>/dev/null); do
            conf_name=$(basename "$conf" .conf)
            if systemctl is-active openvpn-client@$conf_name >/dev/null 2>&1; then
              active_configs+=("$conf_name" "Active OpenVPN configuration")
            fi
          done
          
          if [ ${#active_configs[@]} -eq 0 ]; then
            dialog_info "No Active Connections" "No active OpenVPN connections found."
            log "No active OpenVPN connections found"
            return
          fi
          
          # Let user choose a configuration
          local selected_config=$(dialog_menu "Select Configuration" "Choose an OpenVPN connection to stop:" "${active_configs[@]}")
          
          if [ -z "$selected_config" ]; then
            log "OpenVPN configuration selection cancelled"
            return
          fi
          
          # Stop the connection
          systemctl stop openvpn-client@$selected_config
          
          log "OpenVPN connection stopped: $selected_config"
          dialog_info "OpenVPN Stopped" "OpenVPN connection '$selected_config' has been stopped."
          ;;
      esac
      ;;
    wireguard)
      # Configure WireGuard
      # Check if WireGuard is installed
      if ! command -v wg &> /dev/null; then
        if dialog_confirm "Install WireGuard" "WireGuard is not installed. Would you like to install it?"; then
          apt update
          apt install -y wireguard
          track_installed_package "wireguard"
          log "WireGuard installed"
        else
          dialog_info "WireGuard" "WireGuard is required for this configuration."
          log "WireGuard installation cancelled"
          return
        fi
      fi
      
      # WireGuard options
      local wireguard_option=$(dialog_menu "WireGuard Configuration" "Choose an option:" \
        "import" "Import WireGuard configuration file" \
        "generate" "Generate new WireGuard keys" \
        "status" "WireGuard connection status" \
        "start" "Start WireGuard connection" \
        "stop" "Stop WireGuard connection" \
        "back" "Back to VPN menu")
      
      if [ -z "$wireguard_option" ] || [ "$wireguard_option" = "back" ]; then
        log "WireGuard option selection cancelled"
        return
      fi
      
      case $wireguard_option in
        import)
          # Import WireGuard configuration
          local config_file=$(dialog_input "Configuration File" "Enter the path to the WireGuard configuration file:" "")
          
          if [ -z "$config_file" ]; then
            log "WireGuard configuration file path input cancelled"
            return
          fi
          
          # Check if file exists
          if [ ! -f "$config_file" ]; then
            dialog_info "File Not Found" "The specified configuration file was not found."
            log "WireGuard configuration file not found: $config_file"
            return
          fi
          
          # Ask for interface name
          local interface_name=$(dialog_input "Interface Name" "Enter the WireGuard interface name (e.g., wg0):" "wg0")
          
          if [ -z "$interface_name" ]; then
            log "WireGuard interface name input cancelled"
            return
          fi
          
          # Create WireGuard directory if it doesn't exist
          mkdir -p /etc/wireguard
          
          # Copy the configuration file
          cp "$config_file" "/etc/wireguard/$interface_name.conf"
          
          # Set proper permissions
          chmod 600 "/etc/wireguard/$interface_name.conf"
          
          # Save a backup
          mkdir -p "$BACKUP_DIR/network/wireguard"
          cp "$config_file" "$BACKUP_DIR/network/wireguard/$interface_name.conf.backup.$(date +%Y%m%d%H%M%S)"
          
          log "WireGuard configuration imported: $interface_name"
          
          # Ask if user wants to start the connection
          if dialog_confirm "Start Connection" "Do you want to start the WireGuard connection now?"; then
            # Start the connection
            wg-quick up "$interface_name"
            
            log "WireGuard connection started"
            dialog_info "WireGuard Started" "WireGuard connection has been started."
          else
            dialog_info "Import Completed" "WireGuard configuration has been imported but not started."
          fi
          ;;
        generate)
          # Generate WireGuard keys
          # Ask for interface name
          local interface_name=$(dialog_input "Interface Name" "Enter the WireGuard interface name (e.g., wg0):" "wg0")
          
          if [ -z "$interface_name" ]; then
            log "WireGuard interface name input cancelled"
            return
          fi
          
          # Create WireGuard directory if it doesn't exist
          mkdir -p /etc/wireguard
          
          # Generate private key
          local private_key=$(wg genkey)
          
          # Generate public key
          local public_key=$(echo "$private_key" | wg pubkey)
          
          # Save keys
          echo "$private_key" > "/etc/wireguard/$interface_name.key"
          echo "$public_key" > "/etc/wireguard/$interface_name.pub"
          
          # Set proper permissions
          chmod 600 "/etc/wireguard/$interface_name.key"
          chmod 644 "/etc/wireguard/$interface_name.pub"
          
          # Generate pre-shared key (optional)
          local preshared_key=$(wg genpsk)
          echo "$preshared_key" > "/etc/wireguard/$interface_name.psk"
          chmod 600 "/etc/wireguard/$interface_name.psk"
          
          # Save backup
          mkdir -p "$BACKUP_DIR/network/wireguard"
          echo "$private_key" > "$BACKUP_DIR/network/wireguard/$interface_name.key.$(date +%Y%m%d%H%M%S)"
          echo "$public_key" > "$BACKUP_DIR/network/wireguard/$interface_name.pub.$(date +%Y%m%d%H%M%S)"
          echo "$preshared_key" > "$BACKUP_DIR/network/wireguard/$interface_name.psk.$(date +%Y%m%d%H%M%S)"
          
          log "WireGuard keys generated for interface: $interface_name"
          
          # Show keys
          dialog_info "WireGuard Keys" "WireGuard keys have been generated for interface $interface_name:\n\nPrivate Key: $private_key\nPublic Key: $public_key\nPre-shared Key: $preshared_key\n\nThese keys have been saved to /etc/wireguard/$interface_name.key/pub/psk"
          ;;
        status)
          # Check WireGuard status
          if ! command -v wg &> /dev/null; then
            dialog_info "WireGuard Not Installed" "WireGuard is not installed."
            log "WireGuard not installed"
            return
          fi
          
          local status_output="WIREGUARD INTERFACES:\n\n"
          
          # Check for active interfaces
          local active_interfaces=0
          for interface in $(ip -o link show | grep -oP '(?<=: )(wg[0-9]+)'); do
            status_output+="Interface: $interface (ACTIVE)\n"
            status_output+=$(wg show "$interface")
            status_output+="\n\n"
            active_interfaces=$((active_interfaces + 1))
          done
          
          if [ $active_interfaces -eq 0 ]; then
            status_output+="No active WireGuard interfaces found.\n\n"
          fi
          
          # Check for configured but inactive interfaces
          local config_files=0
          for conf in $(ls -1 /etc/wireguard/*.conf 2>/dev/null); do
            conf_name=$(basename "$conf" .conf)
            if ! ip -o link show | grep -q "$conf_name"; then
              status_output+="Interface: $conf_name (INACTIVE)\n"
              config_files=$((config_files + 1))
            fi
          done
          
          if [ $active_interfaces -eq 0 ] && [ $config_files -eq 0 ]; then
            status_output+="No WireGuard configurations found."
          fi
          
          dialog_info "WireGuard Status" "$status_output"
          ;;
        start)
          # Start WireGuard connection
          local configs=()
          for conf in $(ls -1 /etc/wireguard/*.conf 2>/dev/null); do
            conf_name=$(basename "$conf" .conf)
            # Check if already active
            if ! ip -o link show | grep -q "$conf_name"; then
              configs+=("$conf_name" "WireGuard configuration")
            fi
          done
          
          if [ ${#configs[@]} -eq 0 ]; then
            dialog_info "No Configurations" "No inactive WireGuard configurations found."
            log "No inactive WireGuard configurations found"
            return
          fi
          
          # Let user choose a configuration
          local selected_config=$(dialog_menu "Select Configuration" "Choose a WireGuard configuration to start:" "${configs[@]}")
          
          if [ -z "$selected_config" ]; then
            log "WireGuard configuration selection cancelled"
            return
          fi
          
          # Start the connection
          wg-quick up "$selected_config"
          
          log "WireGuard connection started: $selected_config"
          dialog_info "WireGuard Started" "WireGuard connection '$selected_config' has been started."
          ;;
        stop)
          # Stop WireGuard connection
          local active_configs=()
          for interface in $(ip -o link show | grep -oP '(?<=: )(wg[0-9]+)'); do
            active_configs+=("$interface" "Active WireGuard interface")
          done
          
          if [ ${#active_configs[@]} -eq 0 ]; then
            dialog_info "No Active Connections" "No active WireGuard connections found."
            log "No active WireGuard connections found"
            return
          fi
          
          # Let user choose a configuration
          local selected_config=$(dialog_menu "Select Configuration" "Choose a WireGuard connection to stop:" "${active_configs[@]}")
          
          if [ -z "$selected_config" ]; then
            log "WireGuard configuration selection cancelled"
            return
          fi
          
          # Stop the connection
          wg-quick down "$selected_config"
          
          log "WireGuard connection stopped: $selected_config"
          dialog_info "WireGuard Stopped" "WireGuard connection '$selected_config' has been stopped."
          ;;
      esac
      ;;
    status)
      # VPN connection status
      local status_output="VPN CONNECTION STATUS:\n\n"
      
      # Check OpenVPN
      if command -v openvpn &> /dev/null; then
        status_output+="OPENVPN:\n"
        
        if systemctl is-active openvpn >/dev/null 2>&1; then
          status_output+="Service: ACTIVE\n"
          
          # Check for active connections
          local active_connections=0
          for conn in $(ls -1 /etc/openvpn/client/*.conf 2>/dev/null); do
            conn_name=$(basename "$conn" .conf)
            if systemctl is-active openvpn-client@$conn_name >/dev/null 2>&1; then
              status_output+="- $conn_name (ACTIVE)\n"
              active_connections=$((active_connections + 1))
            fi
          done
          
          if [ $active_connections -eq 0 ]; then
            status_output+="No active OpenVPN connections.\n"
          fi
        else
          status_output+="Service: INACTIVE\n"
        fi
      else
        status_output+="OPENVPN: Not installed\n"
      fi
      
      status_output+="\n"
      
      # Check WireGuard
      if command -v wg &> /dev/null; then
        status_output+="WIREGUARD:\n"
        
        # Check for active interfaces
        local active_interfaces=0
        for interface in $(ip -o link show | grep -oP '(?<=: )(wg[0-9]+)'); do
          status_output+="- $interface (ACTIVE)\n"
          active_interfaces=$((active_interfaces + 1))
        done
        
        if [ $active_interfaces -eq 0 ]; then
          status_output+="No active WireGuard interfaces.\n"
        fi
      else
        status_output+="WIREGUARD: Not installed\n"
      fi
      
      dialog_info "VPN Status" "$status_output"
      ;;
  esac
}

# Function for proxy configuration
configure_proxy() {
  log "Proxy configuration started"
  
  # Menu for proxy options
  local proxy_option=$(dialog_menu "Proxy Configuration" "Choose an option:" \
    "status" "Show current proxy settings" \
    "set" "Set proxy configuration" \
    "clear" "Clear proxy configuration" \
    "back" "Back to network menu")
  
  if [ -z "$proxy_option" ] || [ "$proxy_option" = "back" ]; then
    log "Proxy configuration cancelled"
    return
  fi
  
  case $proxy_option in
    status)
      # Show current proxy settings
      local status_output="SYSTEM PROXY SETTINGS:\n\n"
      
      # Check environment variables
      status_output+="ENVIRONMENT VARIABLES:\n"
      for var in http_proxy https_proxy ftp_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY; do
        if [ -n "${!var}" ]; then
          status_output+="$var=${!var}\n"
        else
          status_output+="$var=<not set>\n"
        fi
      done
      
      status_output+="\nAPT PROXY SETTINGS:\n"
      if [ -f "/etc/apt/apt.conf.d/proxy.conf" ]; then
        status_output+=$(cat "/etc/apt/apt.conf.d/proxy.conf")
      else
        status_output+="No APT proxy configuration found."
      fi
      
      status_output+="\n\nSYSTEM-WIDE PROXY SETTINGS:\n"
      if [ -f "/etc/environment" ]; then
        status_output+=$(grep -i "proxy" /etc/environment || echo "No proxy settings found in /etc/environment")
      else
        status_output+="No system-wide proxy configuration found."
      fi
      
      dialog_info "Proxy Status" "$status_output"
      ;;
    set)
      # Set proxy configuration
      # Ask for HTTP proxy
      local http_proxy=$(dialog_input "HTTP Proxy" "Enter the HTTP proxy URL (e.g., http://proxy.example.com:8080):" "")
      
      if [ -z "$http_proxy" ]; then
        log "HTTP proxy input cancelled"
        return
      fi
      
      # Ask for HTTPS proxy
      local https_proxy=$(dialog_input "HTTPS Proxy" "Enter the HTTPS proxy URL (leave empty to use the same as HTTP):" "")
      
      if [ -z "$https_proxy" ]; then
        https_proxy="$http_proxy"
      fi
      
      # Ask for FTP proxy
      local ftp_proxy=$(dialog_input "FTP Proxy" "Enter the FTP proxy URL (leave empty to use the same as HTTP):" "")
      
      if [ -z "$ftp_proxy" ]; then
        ftp_proxy="$http_proxy"
      fi
      
      # Ask for no_proxy
      local no_proxy=$(dialog_input "No Proxy" "Enter domains to bypass proxy, comma-separated (e.g., localhost,127.0.0.1,.example.com):" "localhost,127.0.0.1")
      
      # Create backup
      mkdir -p "$BACKUP_DIR/network"
      cp /etc/environment "$BACKUP_DIR/network/environment.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
      cp /etc/apt/apt.conf.d/proxy.conf "$BACKUP_DIR/network/apt_proxy.conf.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
      
      # Update environment file
      if grep -q "http_proxy" /etc/environment; then
        sed -i "s|^http_proxy=.*|http_proxy=\"$http_proxy\"|" /etc/environment
      else
        echo "http_proxy=\"$http_proxy\"" >> /etc/environment
      fi
      
      if grep -q "https_proxy" /etc/environment; then
        sed -i "s|^https_proxy=.*|https_proxy=\"$https_proxy\"|" /etc/environment
      else
        echo "https_proxy=\"$https_proxy\"" >> /etc/environment
      fi
      
      if grep -q "ftp_proxy" /etc/environment; then
        sed -i "s|^ftp_proxy=.*|ftp_proxy=\"$ftp_proxy\"|" /etc/environment
      else
        echo "ftp_proxy=\"$ftp_proxy\"" >> /etc/environment
      fi
      
      if grep -q "no_proxy" /etc/environment; then
        sed -i "s|^no_proxy=.*|no_proxy=\"$no_proxy\"|" /etc/environment
      else
        echo "no_proxy=\"$no_proxy\"" >> /etc/environment
      fi
      
      # Set uppercase variables too
      if grep -q "HTTP_PROXY" /etc/environment; then
        sed -i "s|^HTTP_PROXY=.*|HTTP_PROXY=\"$http_proxy\"|" /etc/environment
      else
        echo "HTTP_PROXY=\"$http_proxy\"" >> /etc/environment
      fi
      
      if grep -q "HTTPS_PROXY" /etc/environment; then
        sed -i "s|^HTTPS_PROXY=.*|HTTPS_PROXY=\"$https_proxy\"|" /etc/environment
      else
        echo "HTTPS_PROXY=\"$https_proxy\"" >> /etc/environment
      fi
      
      if grep -q "FTP_PROXY" /etc/environment; then
        sed -i "s|^FTP_PROXY=.*|FTP_PROXY=\"$ftp_proxy\"|" /etc/environment
      else
        echo "FTP_PROXY=\"$ftp_proxy\"" >> /etc/environment
      fi
      
      if grep -q "NO_PROXY" /etc/environment; then
        sed -i "s|^NO_PROXY=.*|NO_PROXY=\"$no_proxy\"|" /etc/environment
      else
        echo "NO_PROXY=\"$no_proxy\"" >> /etc/environment
      fi
      
      # Set APT proxy
      mkdir -p /etc/apt/apt.conf.d
      cat > /etc/apt/apt.conf.d/proxy.conf << EOL
Acquire::http::Proxy "$http_proxy";
Acquire::https::Proxy "$https_proxy";
Acquire::ftp::Proxy "$ftp_proxy";
EOL
      
      log "Proxy configuration set"
      dialog_info "Proxy Configured" "Proxy settings have been configured.\n\nNote: You may need to restart applications or the system for these settings to take effect."
      ;;
    clear)
      # Clear proxy configuration
      if dialog_confirm "Clear Proxy" "Are you sure you want to clear all proxy settings?"; then
        # Create backup
        mkdir -p "$BACKUP_DIR/network"
        cp /etc/environment "$BACKUP_DIR/network/environment.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        cp /etc/apt/apt.conf.d/proxy.conf "$BACKUP_DIR/network/apt_proxy.conf.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        
        # Remove from environment file
        if [ -f "/etc/environment" ]; then
          sed -i '/^http_proxy/d' /etc/environment
          sed -i '/^https_proxy/d' /etc/environment
          sed -i '/^ftp_proxy/d' /etc/environment
          sed -i '/^no_proxy/d' /etc/environment
          sed -i '/^HTTP_PROXY/d' /etc/environment
          sed -i '/^HTTPS_PROXY/d' /etc/environment
          sed -i '/^FTP_PROXY/d' /etc/environment
          sed -i '/^NO_PROXY/d' /etc/environment
        fi
        
        # Remove APT proxy configuration
        if [ -f "/etc/apt/apt.conf.d/proxy.conf" ]; then
          rm -f "/etc/apt/apt.conf.d/proxy.conf"
        fi
        
        log "Proxy configuration cleared"
        dialog_info "Proxy Cleared" "All proxy settings have been cleared.\n\nNote: You may need to restart applications or the system for these changes to take effect."
      else
        log "Clear proxy cancelled"
      fi
      ;;
  esac
}

# Function for DNS configuration
configure_dns() {
  log "DNS configuration started"
  
  # Menu for DNS options
  local dns_option=$(dialog_menu "DNS Configuration" "Choose an option:" \
    "status" "Show current DNS settings" \
    "set" "Set DNS servers" \
    "flush" "Flush DNS cache" \
    "back" "Back to network menu")
  
  if [ -z "$dns_option" ] || [ "$dns_option" = "back" ]; then
    log "DNS configuration cancelled"
    return
  fi
  
  case $dns_option in
    status)
      # Show current DNS settings
      local status_output="CURRENT DNS SETTINGS:\n\n"
      
      # Check resolv.conf
      status_output+="RESOLV.CONF:\n"
      if [ -f "/etc/resolv.conf" ]; then
        status_output+=$(cat "/etc/resolv.conf")
      else
        status_output+="No resolv.conf file found."
      fi
      
      # Check systemd-resolved if available
      if command -v resolvectl &> /dev/null; then
        status_output+="\n\nSYSTEMD-RESOLVED STATUS:\n"
        status_output+=$(resolvectl status)
      fi
      
      # Check NetworkManager if available
      if command -v nmcli &> /dev/null; then
        status_output+="\n\nNETWORKMANAGER DNS SETTINGS:\n"
        status_output+=$(nmcli device show | grep -i dns)
      fi
      
      dialog_info "DNS Status" "$status_output"
      ;;
    set)
      # Set DNS servers
      # Ask for primary DNS
      local primary_dns=$(dialog_input "Primary DNS" "Enter the primary DNS server IP address:" "8.8.8.8")
      
      if [ -z "$primary_dns" ]; then
        log "Primary DNS input cancelled"
        return
      fi
      
      # Ask for secondary DNS
      local secondary_dns=$(dialog_input "Secondary DNS" "Enter the secondary DNS server IP address (optional):" "8.8.4.4")
      
      # Ask for management method
      local dns_method=$(dialog_menu "DNS Configuration Method" "How do you want to configure DNS?" \
        "resolv" "Edit resolv.conf directly" \
        "netplan" "Configure via Netplan (recommended for Ubuntu 18.04+)" \
        "systemd" "Configure via systemd-resolved" \
        "back" "Cancel")
      
      if [ -z "$dns_method" ] || [ "$dns_method" = "back" ]; then
        log "DNS method selection cancelled"
        return
      fi
      
      # Create backup
      mkdir -p "$BACKUP_DIR/network"
      
      case $dns_method in
        resolv)
          # Backup resolv.conf
          cp /etc/resolv.conf "$BACKUP_DIR/network/resolv.conf.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
          
          # Check if resolv.conf is a symlink
          if [ -L "/etc/resolv.conf" ]; then
            if dialog_confirm "Symlink Warning" "The file /etc/resolv.conf is a symlink. Modifying it directly may not work or changes may be overwritten.\n\nDo you want to proceed anyway?"; then
              # Remove symlink and create a real file
              rm /etc/resolv.conf
              touch /etc/resolv.conf
            else
              log "DNS configuration cancelled due to symlink"
              return
            fi
          fi
          
          # Create new resolv.conf
          cat > /etc/resolv.conf << EOL
# Generated by Ubuntu Setup Script
nameserver $primary_dns
EOL
          
          if [ ! -z "$secondary_dns" ]; then
            echo "nameserver $secondary_dns" >> /etc/resolv.conf
          fi
          
          # Make file immutable to prevent overwriting
          if dialog_confirm "File Protection" "Do you want to make resolv.conf immutable to prevent it from being overwritten by the system?"; then
            chattr +i /etc/resolv.conf
            log "resolv.conf made immutable"
          fi
          
          log "DNS servers set via resolv.conf"
          dialog_info "DNS Configured" "DNS servers have been configured via resolv.conf.\n\nPrimary DNS: $primary_dns\nSecondary DNS: $secondary_dns"
          ;;
        netplan)
          # Configure via Netplan
          local netplan_files=( $(find /etc/netplan -name "*.yaml") )
          
          if [ ${#netplan_files[@]} -eq 0 ]; then
            dialog_info "No Netplan Files" "No Netplan configuration files found."
            log "No Netplan configuration files found"
            return
          fi
          
          # Build options
          local netplan_options=()
          for file in "${netplan_files[@]}"; do
            netplan_options+=("$file" "Netplan configuration file")
          done
          
          # Let user choose a file
          local selected_file=$(dialog_menu "Select Netplan File" "Choose a Netplan configuration file to modify:" "${netplan_options[@]}")
          
          if [ -z "$selected_file" ]; then
            log "Netplan file selection cancelled"
            return
          fi
          
          # Backup the file
          cp "$selected_file" "$BACKUP_DIR/network/$(basename "$selected_file").backup.$(date +%Y%m%d%H%M%S)"
          
          # Read the file
          local netplan_content=$(cat "$selected_file")
          
          # Check if nameservers section exists
          if grep -q "nameservers:" "$selected_file"; then
            # Update existing nameservers
            local temp_file=$(mktemp)
            
            awk -v primary="$primary_dns" -v secondary="$secondary_dns" '
              /nameservers:/ {
                print $0;
                inside_ns = 1;
                ns_printed = 0;
                next;
              }
              
              /addresses:/ && inside_ns {
                print "      addresses:";
                print "        - " primary;
                if (secondary != "") {
                  print "        - " secondary;
                }
                ns_printed = 1;
                next;
              }
              
              /^ *- / && inside_ns && /addresses:/ {
                if (!ns_printed) {
                  next;
                }
              }
              
              /^ *[a-z]/ && inside_ns {
                inside_ns = 0;
              }
              
              {print $0}
            ' "$selected_file" > "$temp_file"
            
            mv "$temp_file" "$selected_file"
          else
            # Add nameservers section to the first interface
            local temp_file=$(mktemp)
            
            awk -v primary="$primary_dns" -v secondary="$secondary_dns" '
              /ethernets:/ {
                print $0;
                inside_eth = 1;
                next;
              }
              
              /^ *[a-z]/ && inside_eth && !interface_found {
                print $0;
                interface_found = 1;
                indent = index($0, $1) - 1;
                spaces = "                    "; # Plenty of spaces for indentation
                sub_indent = spaces;
                gsub(/./, " ", sub_indent);
                sub_indent = substr(sub_indent, 1, indent + 2);
                next;
              }
              
              interface_found && !ns_added && /^ *[a-z]/ && $1 !~ /nameservers:/ {
                print $0;
                if (1) {
                  print sub_indent "nameservers:";
                  print sub_indent "  addresses:";
                  print sub_indent "    - " primary;
                  if (secondary != "") {
                    print sub_indent "    - " secondary;
                  }
                  ns_added = 1;
                }
                next;
              }
              
              {print $0}
            ' "$selected_file" > "$temp_file"
            
            mv "$temp_file" "$selected_file"
          fi
          
          # Apply netplan configuration
          netplan apply
          
          log "DNS servers set via Netplan"
          dialog_info "DNS Configured" "DNS servers have been configured via Netplan.\n\nPrimary DNS: $primary_dns\nSecondary DNS: $secondary_dns\n\nThe configuration has been applied."
          ;;
        systemd)
          # Configure via systemd-resolved
          if ! command -v systemd-resolve &> /dev/null; then
            dialog_info "systemd-resolved Not Available" "systemd-resolved is not available on this system."
            log "systemd-resolved not available"
            return
          fi
          
          # List network interfaces
          mapfile -t interface_list < <(ls /sys/class/net/ | grep -v "lo\|docker")
          
          if [ ${#interface_list[@]} -eq 0 ]; then
            dialog_info "No Interfaces" "No network interfaces found."
            log "No network interfaces found"
            return
          fi
          
          # Build menu options with interfaces
          local options=()
          for ((i=0; i<${#interface_list[@]}; i++)); do
            options+=("${interface_list[$i]}" "Network interface")
          done
          
          # Let user choose an interface
          local selected_interface=$(dialog_menu "Select Interface" "Choose a network interface for DNS configuration:" "${options[@]}")
          
          if [ -z "$selected_interface" ]; then
            log "Interface selection cancelled"
            return
          fi
          
          # Set DNS servers
          local dns_servers="$primary_dns"
          if [ ! -z "$secondary_dns" ]; then
            dns_servers="$dns_servers $secondary_dns"
          fi
          
          systemd-resolve --interface="$selected_interface" --set-dns="$primary_dns" --set-domain=~.
          
          if [ ! -z "$secondary_dns" ]; then
            systemd-resolve --interface="$selected_interface" --set-dns="$secondary_dns" --set-domain=~.
          fi
          
          # Enable systemd-resolved
          systemctl enable systemd-resolved
          systemctl restart systemd-resolved
          
          log "DNS servers set via systemd-resolved"
          dialog_info "DNS Configured" "DNS servers have been configured via systemd-resolved.\n\nPrimary DNS: $primary_dns\nSecondary DNS: $secondary_dns\n\nThe configuration has been applied to interface $selected_interface."
          ;;
      esac
      ;;
    flush)
      # Flush DNS cache
      local flush_output=""
      
      # Check for different DNS cache providers
      if command -v systemd-resolve &> /dev/null; then
        systemd-resolve --flush-caches
        flush_output+="systemd-resolved DNS cache flushed.\n"
      fi
      
      if command -v nscd &> /dev/null; then
        if systemctl status nscd >/dev/null 2>&1; then
          systemctl restart nscd
          flush_output+="nscd cache flushed.\n"
        fi
      fi
      
      if command -v resolvectl &> /dev/null; then
        resolvectl flush-caches
        flush_output+="resolvectl cache flushed.\n"
      fi
      
      # Restart services that might have DNS cache
      if systemctl status dnsmasq >/dev/null 2>&1; then
        systemctl restart dnsmasq
        flush_output+="dnsmasq restarted.\n"
      fi
      
      if [ -z "$flush_output" ]; then
        flush_output="No DNS cache providers found to flush."
      fi
      
      log "DNS cache flush attempted"
      dialog_info "DNS Cache Flushed" "$flush_output"
      ;;
  esac
}

#######################################
# SSH FUNCTIONS
#######################################

# Function for securing OpenSSH
secure_ssh() {
  log "OpenSSH security started"
  
  # Ask for confirmation
  if ! dialog_confirm "Secure OpenSSH" "Do you want to proceed with securing OpenSSH?\n\nThis process:\n- Creates or uses existing SSH keys\n- Configures SSH for better security\n- Can disable password authentication"; then
    log "OpenSSH security cancelled by user"
    return
  fi
  
  # Check if OpenSSH server is installed
  if ! dpkg -l | grep -q openssh-server; then
    log "OpenSSH server is not installed"
    if dialog_confirm "Install OpenSSH" "OpenSSH server is not installed. Do you want to install it now?"; then
      log "Installing OpenSSH server"
      apt update
      apt install -y openssh-server
    else
      dialog_info "Secure OpenSSH" "OpenSSH server is needed to continue. Action aborted."
      log "User decided not to install OpenSSH"
      return
    fi
  fi
  
  # Backup SSH configuration
  local backup_file="$BACKUP_DIR/ssh/sshd_config.backup.$(date +%Y%m%d%H%M%S)"
  mkdir -p "$BACKUP_DIR/ssh"
  cp /etc/ssh/sshd_config "$backup_file"
  log "Backed up SSH configuration to $backup_file"
  
  # Ask for SSH port
  local SSH_PORT=$(dialog_input "SSH Port" "Enter the desired SSH port (default: 22):" "22")
  if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
  fi
  log "Selected SSH port: $SSH_PORT"
  
  # Validate port number
  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    dialog_info "Invalid Port" "The port number must be between 1 and 65535."
    log "Invalid SSH port number: $SSH_PORT"
    return
  fi
  
  # Get users and let user choose
  log "Getting users for SSH keys"
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    dialog_info "Secure OpenSSH" "No normal users found on the system."
    log "No normal users found"
    return
  fi
  
  # Build menu options with users
  local options=()
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+=("$i" "${user_list[$i]}")
  done
  
  # Let user choose
  local selection=$(dialog_menu "Select User" "Choose a user for SSH keys:" "${options[@]}")
  
  if [ -z "$selection" ]; then
    log "User selection cancelled"
    return
  fi
  
  local SSH_USER="${user_list[$selection]}"
  log "Selected user for SSH keys: $SSH_USER"
  
  # Choose key type
  local key_type=$(dialog_menu "SSH Key Type" "Choose an SSH key type:" \
    "ed25519" "ED25519 (recommended, more secure)" \
    "rsa" "RSA 4096-bit (more compatible)" \
    "ecdsa" "ECDSA (balanced security and compatibility)")
  
  if [ -z "$key_type" ]; then
    log "Key type selection cancelled"
    return
  fi
  
  # ED25519 keys creation or use existing
  log "Checking/creating $key_type SSH keys"
  local USER_HOME=$(eval echo ~$SSH_USER)
  local SSH_DIR="$USER_HOME/.ssh"
  
  if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown $SSH_USER:$SSH_USER "$SSH_DIR"
  fi
  
  # Generate the keys based on selected type
  local KEY_FILE="$SSH_DIR/id_$key_type"
  local KEY_GENERATED=0
  local KEY_PUB=""
  local KEY_PRIV=""
  
  if [ ! -f "$KEY_FILE" ]; then
    log "Creating new $key_type keys"
    
    # Different key generation based on type
    case $key_type in
      ed25519)
        sudo -u $SSH_USER ssh-keygen -t ed25519 -a 100 -f "$KEY_FILE" -N ""
        ;;
      rsa)
        sudo -u $SSH_USER ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N ""
        ;;
      ecdsa)
        sudo -u $SSH_USER ssh-keygen -t ecdsa -b 521 -f "$KEY_FILE" -N ""
        ;;
    esac
    
    KEY_GENERATED=1
    dialog_info "SSH Keys" "New $key_type keys created."
  else
    log "Existing $key_type keys found"
    KEY_PUB=$(cat "$KEY_FILE.pub")
    dialog_info "SSH Keys" "Existing $key_type keys will be used."
  fi
  
  # Make sure the authorized_keys file exists and has the right permissions
  local AUTH_KEYS="$SSH_DIR/authorized_keys"
  if [ ! -f "$AUTH_KEYS" ]; then
    sudo -u $SSH_USER touch "$AUTH_KEYS"
  fi
  
  cat "$KEY_FILE.pub" >> "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  chown $SSH_USER:$SSH_USER "$AUTH_KEYS"
  
  # Create backup copies of the keys
  mkdir -p "$BACKUP_DIR/ssh_keys/$SSH_USER"
  cp "$KEY_FILE" "$BACKUP_DIR/ssh_keys/$SSH_USER/id_${key_type}.backup.$(date +%Y%m%d%H%M%S)"
  cp "$KEY_FILE.pub" "$BACKUP_DIR/ssh_keys/$SSH_USER/id_${key_type}.pub.backup.$(date +%Y%m%d%H%M%S)"
  
  # SSH configuration adjustment
  log "Adjusting SSH configuration"
  
  # Authentication method choice
  local auth_option=$(dialog_menu "SSH Authentication" "Choose the authentication method:" \
    "1" "Keys only (disable passwords)" \
    "2" "Allow both keys and passwords" \
    "3" "Advanced security configuration")
  
  if [ -z "$auth_option" ]; then
    log "Authentication method selection cancelled"
    return
  fi
  
  # Protocol and keys
  sed -i 's/^#Protocol 2/Protocol 2/' /etc/ssh/sshd_config
  
  # Protocol 1 is insecure
  sed -i '/^Protocol 1/d' /etc/ssh/sshd_config
  
  # Prefer modern keys
  sed -i 's/^HostKey \/etc\/ssh\/ssh_host_rsa_key/#HostKey \/etc\/ssh\/ssh_host_rsa_key/' /etc/ssh/sshd_config
  sed -i 's/^HostKey \/etc\/ssh\/ssh_host_ecdsa_key/#HostKey \/etc\/ssh\/ssh_host_ecdsa_key/' /etc/ssh/sshd_config
  sed -i 's/^#HostKey \/etc\/ssh\/ssh_host_ed25519_key/HostKey \/etc\/ssh\/ssh_host_ed25519_key/' /etc/ssh/sshd_config
  
  # SSH port change
  if grep -q "^#Port 22" /etc/ssh/sshd_config; then
    sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
  elif grep -q "^Port " /etc/ssh/sshd_config; then
    sed -i "s/^Port [0-9]*/Port $SSH_PORT/" /etc/ssh/sshd_config
  else
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
  fi
  
  # Key authentication enable
  sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  
  # Configure based on selected authentication method
  if [ "$auth_option" = "1" ]; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    log "Password authentication disabled"
  elif [ "$auth_option" = "2" ]; then
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    log "Password authentication remains enabled"
  elif [ "$auth_option" = "3" ]; then
    # Advanced configuration
    if dialog_confirm "Advanced Security" "Apply additional security hardening measures to SSH?\n\nThis includes:\n- Disable root login\n- Restrict SSH users\n- Set login grace time\n- Limit authentication attempts\n- Use strong ciphers"; then
      # Disable root login
      sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
      
      # Allow only specific users to use SSH
      local allow_users=$(dialog_input "SSH Users" "Enter a space-separated list of users allowed to use SSH (leave empty for all users):" "$SSH_USER")
      
      if [ ! -z "$allow_users" ]; then
        if grep -q "^AllowUsers" /etc/ssh/sshd_config; then
          sed -i "s/^AllowUsers.*/AllowUsers $allow_users/" /etc/ssh/sshd_config
        else
          echo "AllowUsers $allow_users" >> /etc/ssh/sshd_config
        fi
        log "SSH access restricted to users: $allow_users"
      fi
      
      # Set login grace time
      sed -i 's/^#LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
      
      # Set maximum authentication attempts
      sed -i 's/^#MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
      
      # Strong ciphers and algorithms
      cat >> /etc/ssh/sshd_config << EOL

# Security hardening
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
EOL
      
      log "Advanced SSH security configured"
    fi
    
    # Password authentication (ask separately in advanced mode)
    local pwd_auth=$(dialog_menu "Password Authentication" "Allow password authentication?" \
      "no" "Disable password authentication (keys only)" \
      "yes" "Allow password authentication")
    
    if [ "$pwd_auth" = "no" ]; then
      sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      log "Password authentication disabled"
    else
      sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
      sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
      log "Password authentication enabled"
    fi
    
    # 2FA authentication with Google Authenticator
    if dialog_confirm "Two-Factor Authentication" "Do you want to set up two-factor authentication (2FA) with Google Authenticator?"; then
      # Install Google Authenticator
      apt update
      apt install -y libpam-google-authenticator
      track_installed_package "libpam-google-authenticator"
      
      # Configure PAM
      sed -i 's/^@include common-auth/#@include common-auth/' /etc/pam.d/sshd
      echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
      
      # Configure SSH
      sed -i 's/^ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
      sed -i 's/^#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
      
      # Add AuthenticationMethods line
      if ! grep -q "^AuthenticationMethods" /etc/ssh/sshd_config; then
        echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
      else
        sed -i 's/^AuthenticationMethods.*/AuthenticationMethods publickey,keyboard-interactive/' /etc/ssh/sshd_config
      fi
      
      log "Google Authenticator 2FA configured"
      dialog_info "2FA Setup" "Google Authenticator has been installed and configured.\n\nEach user will need to run the 'google-authenticator' command to set up their own 2FA tokens."
    fi
  fi
  
  # Other security settings
  sed -i 's/^#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
  sed -i 's/^ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  
  # Restart SSH service
  log "Restarting SSH service"
  systemctl restart ssh
  
  # Key information for the result screen
  local ssh_info=""
  ssh_info+="SSH security configuration completed:\n\n"
  ssh_info+="1. SSH port is set to: $SSH_PORT\n"
  if [ "$auth_option" = "1" ]; then
    ssh_info+="2. Password authentication is disabled\n"
    ssh_info+="3. Only key authentication is allowed\n"
  elif [ "$auth_option" = "2" ]; then
    ssh_info+="2. Password authentication is enabled\n"
    ssh_info+="3. Both keys and passwords are allowed\n"
  elif [ "$auth_option" = "3" ]; then
    ssh_info+="2. Advanced security settings applied\n"
    if [ "$pwd_auth" = "no" ]; then
      ssh_info+="3. Password authentication is disabled\n"
    else
      ssh_info+="3. Password authentication is enabled\n"
    fi
  fi
  
  # Show private and public keys
  local key_info=""
  local pub_key=$(cat "$KEY_FILE.pub")
  local priv_key=$(cat "$KEY_FILE")
  
  key_info+="SSH $key_type keys for user $SSH_USER:\n\n"
  key_info+="Public key (place this on the server in ~/.ssh/authorized_keys):\n"
  key_info+="$pub_key\n\n"
  key_info+="Private key (keep this secure on your client and NEVER share it):\n"
  key_info+="$priv_key\n\n"
  key_info+="Instructions for SSH connection from your client:\n"
  key_info+="1. Save the above private key in a file on your client (e.g., id_${key_type})\n"
  key_info+="2. Set the correct permissions: chmod 600 id_${key_type}\n"
  key_info+="3. Use the following command to connect:\n"
  key_info+="   ssh -i /path/to/id_${key_type} -p $SSH_PORT $SSH_USER@your-server-ip\n\n"
  key_info+="Note: A backup of these keys has been saved to $BACKUP_DIR/ssh_keys/$SSH_USER/"
  
  # Show results
  log "OpenSSH security configuration completed"
  
  # Show SSH configuration
  dialog_info "SSH Security" "$ssh_info"
  
  # Show key information
  dialog_info "SSH Keys" "$key_info"
  
  # Show private key separately
  dialog_info "IMPORTANT KEY INFORMATION" "Private key (keep this secure on your client):\n\n$priv_key\n\nMake sure you copy this key and store it safely before closing this window!"
}

# Function for SSH key management
manage_ssh_keys() {
  log "SSH key management started"
  
  # Check if SSH server is installed
  if ! dpkg -l | grep -q openssh-server; then
    log "OpenSSH server is not installed"
    if dialog_confirm "Install OpenSSH" "OpenSSH server is not installed. Do you want to install it now?"; then
      log "Installing OpenSSH server"
      apt update
      apt install -y openssh-server
    else
      dialog_info "SSH Key Management" "OpenSSH server is needed to continue. Action aborted."
      log "User decided not to install OpenSSH"
      return
    fi
  fi
  
  # Get users and let choose
  log "Getting users for SSH key management"
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    dialog_info "SSH Key Management" "No normal users found on the system."
    log "No normal users found"
    return
  fi
  
  # Build menu options with users
  local options=()
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+=("$i" "${user_list[$i]}")
  done
  
  # Let user choose
  local selection=$(dialog_menu "Select User" "Choose a user for SSH key management:" "${options[@]}")
  
  if [ -z "$selection" ]; then
    log "User selection cancelled"
    return
  fi
  
  local user="${user_list[$selection]}"
  log "Selected user for SSH key management: $user"
  
  # SSH directory and files
  local user_home=$(eval echo ~$user)
  local ssh_dir="$user_home/.ssh"
  local auth_keys="$ssh_dir/authorized_keys"
  
  # Check if SSH directory exists
  if [ ! -d "$ssh_dir" ]; then
    # Create SSH directory
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown $user:$user "$ssh_dir"
    log "SSH directory created for user $user"
  fi
  
  # Check if authorized_keys exists
  if [ ! -f "$auth_keys" ]; then
    # Create authorized_keys
    touch "$auth_keys"
    chmod 600 "$auth_keys"
    chown $user:$user "$auth_keys"
    log "authorized_keys file created for user $user"
  fi
  
  while true; do
    # SSH key management menu
    local action=$(dialog_menu "SSH Key Management" "Choose an action for user $user:" \
      "list" "Show existing keys" \
      "create" "Create new SSH key" \
      "import" "Import SSH key" \
      "delete" "Delete SSH key" \
      "export" "Export private key for use on client" \
      "rotate" "SSH key rotation (replace)" \
      "back" "Back")
    
    case $action in
      list)
        # Show existing keys
        local key_files=$(find "$ssh_dir" -name "id_*" -not -name "*.pub" 2>/dev/null)
        local key_count=$(echo "$key_files" | grep -v "^$" | wc -l)
        
        local key_info="SSH keys for user $user:\n\n"
        
        if [ $key_count -eq 0 ]; then
          key_info+="No SSH keys found.\n"
        else
          for key_file in $key_files; do
            local key_type=$(basename "$key_file" | sed 's/^id_//')
            key_info+="- $key_type key: $key_file\n"
          done
        fi
        
        # Show authorized public keys
        if [ -f "$auth_keys" ]; then
          local auth_key_count=$(grep -v "^$" "$auth_keys" | wc -l)
          key_info+="\nAuthorized public keys ($auth_key_count):\n"
          
          if [ $auth_key_count -gt 0 ]; then
            local counter=1
            while read -r line; do
              if [ -n "$line" ]; then
                local key_comment=$(echo "$line" | awk '{print $3}')
                local key_type=$(echo "$line" | awk '{print $1}')
                key_info+="$counter. $key_type - $key_comment\n"
                counter=$((counter + 1))
              fi
            done < "$auth_keys"
          else
            key_info+="No authorized public keys found.\n"
          fi
        else
          key_info+="\nNo authorized_keys file found.\n"
        fi
        
        dialog_info "SSH Keys" "$key_info"
        ;;
      create)
        # Create new SSH key
        local key_type=$(dialog_menu "Key Type" "Choose the type of SSH key:" \
          "ed25519" "ED25519 (recommended)" \
          "rsa" "RSA (4096 bits)" \
          "ecdsa" "ECDSA" \
          "dsa" "DSA (old, not recommended)")
        
        if [ -z "$key_type" ]; then
          log "Key type selection cancelled"
          continue
        fi
        
        local key_file="$ssh_dir/id_$key_type"
        local key_comment=$(dialog_input "Key Comment" "Enter a comment for the key (e.g., username@device):" "$user@$(hostname)")
        
        # Check if key already exists
        if [ -f "$key_file" ]; then
          if ! dialog_confirm "Overwrite Key" "A $key_type key already exists. Do you want to overwrite it?"; then
            log "Key overwrite cancelled"
            continue
          fi
        fi
        
        # Create backup directory
        mkdir -p "$BACKUP_DIR/ssh_keys/$user"
        
        # Back up existing key if it exists
        if [ -f "$key_file" ]; then
          cp "$key_file" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.backup.$(date +%Y%m%d%H%M%S)"
          cp "$key_file.pub" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        fi
        
        # Generate the key
        log "Creating SSH $key_type key for $user"
        if [ "$key_type" = "rsa" ]; then
          sudo -u $user ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "$key_comment"
        elif [ "$key_type" = "ed25519" ]; then
          sudo -u $user ssh-keygen -t ed25519 -a 100 -f "$key_file" -N "" -C "$key_comment"
        else
          sudo -u $user ssh-keygen -t $key_type -f "$key_file" -N "" -C "$key_comment"
        fi
        
        # Add public key to authorized_keys
        if dialog_confirm "Authorize" "Do you want to add the new public key to the authorized keys?"; then
          cat "$key_file.pub" >> "$auth_keys"
          chmod 600 "$auth_keys"
          chown $user:$user "$auth_keys"
          log "Public key added to authorized_keys for $user"
        fi
        
        # Copy key to backup directory
        cp "$key_file" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.$(date +%Y%m%d%H%M%S)"
        cp "$key_file.pub" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.$(date +%Y%m%d%H%M%S)"
        
        # Show key information
        dialog_info "Key Created" "SSH $key_type key has been created.\n\nPrivate key: $key_file\nPublic key: $key_file.pub\n\nA backup has been saved to $BACKUP_DIR/ssh_keys/$user/"
        
        # Show public key
        local pub_key=$(cat "$key_file.pub")
        dialog_info "Public Key" "Public key ($key_type):\n\n$pub_key"
        
        # Show private key
        local priv_key=$(cat "$key_file")
        dialog_info "Private Key" "Private key ($key_type):\n\nKEEP THIS KEY SAFE AND NEVER SHARE IT!\n\n$priv_key"
        ;;
      import)
        # Import SSH key
        local import_type=$(dialog_menu "Import Type" "What do you want to import?" \
          "pubkey" "Public key (add to authorized_keys)" \
          "both" "Both public and private key")
        
        if [ -z "$import_type" ]; then
          log "Import type selection cancelled"
          continue
        fi
        
        if [ "$import_type" = "pubkey" ]; then
          # Import public key
          local pubkey=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Import Public Key" \
            --inputbox "Paste the public key (starts with ssh-...):" 15 70 "" 3>&1 1>&2 2>&3)
          
          if [ -z "$pubkey" ]; then
            log "Public key import cancelled"
            continue
          fi
          
          # Check if key looks valid
          if ! echo "$pubkey" | grep -q "^ssh-.*"; then
            dialog_info "Invalid Key" "The key doesn't appear to be a valid SSH public key. It should start with 'ssh-'."
            log "Invalid public key format"
            continue
          fi
          
          # Add to authorized_keys
          echo "$pubkey" >> "$auth_keys"
          chmod 600 "$auth_keys"
          chown $user:$user "$auth_keys"
          log "Public key imported for $user"
          
          dialog_info "Public Key Imported" "The public key has been added to the authorized keys for $user."
        else
          # Import both keys
          local key_type=$(dialog_menu "Key Type" "Which type of key are you importing?" \
            "ed25519" "ED25519" \
            "rsa" "RSA" \
            "ecdsa" "ECDSA" \
            "dsa" "DSA")
          
          if [ -z "$key_type" ]; then
            log "Key type selection cancelled"
            continue
          fi
          
          local key_file="$ssh_dir/id_$key_type"
          
          # Check if key already exists
          if [ -f "$key_file" ]; then
            if ! dialog_confirm "Overwrite Key" "A $key_type key already exists. Do you want to overwrite it?"; then
              log "Key overwrite cancelled"
              continue
            fi
          fi
          
          # Import private key
          local privkey=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Import Private Key" \
            --inputbox "Paste the private key (starts with -----BEGIN):" 20 70 "" 3>&1 1>&2 2>&3)
          
          if [ -z "$privkey" ]; then
            log "Private key import cancelled"
            continue
          fi
          
          # Check if key looks valid
          if ! echo "$privkey" | grep -q "^-----BEGIN"; then
            dialog_info "Invalid Key" "The key doesn't appear to be a valid SSH private key. It should start with '-----BEGIN'."
            log "Invalid private key format"
            continue
          fi
          
          # Import public key
          local pubkey=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Import Public Key" \
            --inputbox "Paste the corresponding public key (starts with ssh-...):" 15 70 "" 3>&1 1>&2 2>&3)
          
          if [ -z "$pubkey" ]; then
            log "Public key import cancelled"
            continue
          fi
          
          # Check if key looks valid
          if ! echo "$pubkey" | grep -q "^ssh-"; then
            dialog_info "Invalid Key" "The key doesn't appear to be a valid SSH public key. It should start with 'ssh-'."
            log "Invalid public key format"
            continue
          fi
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/ssh_keys/$user"
          
          # Back up existing key if it exists
          if [ -f "$key_file" ]; then
            cp "$key_file" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.backup.$(date +%Y%m%d%H%M%S)"
            cp "$key_file.pub" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
          fi
          
          # Write keys to files
          echo "$privkey" > "$key_file"
          echo "$pubkey" > "$key_file.pub"
          chmod 600 "$key_file"
          chmod 644 "$key_file.pub"
          chown $user:$user "$key_file"
          chown $user:$user "$key_file.pub"
          
          # Copy keys to backup directory
          echo "$privkey" > "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.$(date +%Y%m%d%H%M%S)"
          echo "$pubkey" > "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.$(date +%Y%m%d%H%M%S)"
          
          # Add public key to authorized_keys
          if dialog_confirm "Authorize" "Do you want to add the imported public key to the authorized keys?"; then
            echo "$pubkey" >> "$auth_keys"
            chmod 600 "$auth_keys"
            chown $user:$user "$auth_keys"
            log "Imported public key added to authorized_keys for $user"
          fi
          
          log "SSH keys imported for $user"
          dialog_info "Keys Imported" "SSH $key_type keys have been imported for $user.\n\nBackups have been saved to $BACKUP_DIR/ssh_keys/$user/"
        fi
        ;;
      delete)
        # Delete SSH key
        local delete_type=$(dialog_menu "Delete Type" "What do you want to delete?" \
          "key" "SSH key pair (private and public key)" \
          "auth" "Authorized public key from authorized_keys")
        
        if [ -z "$delete_type" ]; then
          log "Delete type selection cancelled"
          continue
        fi
        
        if [ "$delete_type" = "key" ]; then
          # Delete key pair
          local key_files=$(find "$ssh_dir" -name "id_*" -not -name "*.pub" 2>/dev/null)
          local key_options=()
          local key_counter=0
          
          for key_file in $key_files; do
            local key_type=$(basename "$key_file" | sed 's/^id_//')
            key_options+=("$key_counter" "$key_type key ($key_file)")
            key_counter=$((key_counter + 1))
          done
          
          if [ $key_counter -eq 0 ]; then
            dialog_info "No Keys" "No SSH keys found to delete."
            continue
          fi
          
          local key_selection=$(dialog_menu "Select Key" "Select the key to delete:" "${key_options[@]}")
          
          if [ -z "$key_selection" ]; then
            log "Key selection cancelled"
            continue
          fi
          
          local selected_key=$(echo "$key_files" | sed -n "$((key_selection + 1))p")
          local key_type=$(basename "$selected_key" | sed 's/^id_//')
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/ssh_keys/$user"
          
          # Back up key before deletion
          cp "$selected_key" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.backup.$(date +%Y%m%d%H%M%S)"
          cp "$selected_key.pub" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
          
          if dialog_confirm "Delete Key" "Are you sure you want to delete the $key_type key?\n\n$selected_key"; then
            rm -f "$selected_key" "$selected_key.pub"
            log "SSH $key_type key deleted for $user"
            dialog_info "Key Deleted" "SSH $key_type key has been deleted.\n\nA backup has been saved to $BACKUP_DIR/ssh_keys/$user/"
          else
            log "Key deletion cancelled"
          fi
        else
          # Delete authorized key
          if [ ! -f "$auth_keys" ]; then
            dialog_info "No Keys" "No authorized_keys file found."
            continue
          fi
          
          local auth_key_count=$(grep -v "^$" "$auth_keys" | wc -l)
          if [ $auth_key_count -eq 0 ]; then
            dialog_info "No Keys" "No authorized keys found to delete."
            continue
          fi
          
          local auth_key_options=()
          local counter=1
          
          while read -r line; do
            if [ -n "$line" ]; then
              local key_comment=$(echo "$line" | awk '{print $3}')
              local key_type=$(echo "$line" | awk '{print $1}')
              auth_key_options+=("$counter" "$key_type - $key_comment")
              counter=$((counter + 1))
            fi
          done < "$auth_keys"
          
          local auth_selection=$(dialog_menu "Select Key" "Select the authorized key to delete:" "${auth_key_options[@]}")
          
          if [ -z "$auth_selection" ]; then
            log "Authorized key selection cancelled"
            continue
          fi
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/ssh_keys/$user"
          
          # Back up authorized_keys before deletion
          cp "$auth_keys" "$BACKUP_DIR/ssh_keys/$user/authorized_keys.backup.$(date +%Y%m%d%H%M%S)"
          
          # Delete the selected key
          local temp_file=$(mktemp)
          sed "${auth_selection}d" "$auth_keys" > "$temp_file"
          mv "$temp_file" "$auth_keys"
          chmod 600 "$auth_keys"
          chown $user:$user "$auth_keys"
          
          log "Authorized key deleted for $user"
          dialog_info "Key Deleted" "The selected authorized key has been deleted.\n\nA backup has been saved to $BACKUP_DIR/ssh_keys/$user/"
        fi
        ;;
      export)
        # Export private key for use on client
        local key_files=$(find "$ssh_dir" -name "id_*" -not -name "*.pub" 2>/dev/null)
        local key_options=()
        local key_counter=0
        
        for key_file in $key_files; do
          local key_type=$(basename "$key_file" | sed 's/^id_//')
          key_options+=("$key_counter" "$key_type key ($key_file)")
          key_counter=$((key_counter + 1))
        done
        
        if [ $key_counter -eq 0 ]; then
          dialog_info "No Keys" "No SSH keys found to export."
          continue
        fi
        
        local key_selection=$(dialog_menu "Select Key" "Select the key to export:" "${key_options[@]}")
        
        if [ -z "$key_selection" ]; then
          log "Key selection cancelled"
          continue
        fi
        
        local selected_key=$(echo "$key_files" | sed -n "$((key_selection + 1))p")
        local key_type=$(basename "$selected_key" | sed 's/^id_//')
        
        # Export format options
        local export_format=$(dialog_menu "Export Format" "Choose an export format:" \
          "display" "Display key for copying" \
          "file" "Save to file" \
          "qr" "Generate QR code (for mobile devices)")
        
        if [ -z "$export_format" ]; then
          log "Export format selection cancelled"
          continue
        fi
        
        local priv_key=$(cat "$selected_key")
        
        case $export_format in
          display)
            # Display key for copying
            dialog_info "Private Key" "Private key ($key_type):\n\nKEEP THIS KEY SAFE AND NEVER SHARE IT!\n\n$priv_key"
            ;;
          file)
            # Save to file
            local export_dir="$HOME/ssh_export"
            mkdir -p "$export_dir"
            
            local export_file="$export_dir/id_${key_type}_${user}_$(date +%Y%m%d)"
            echo "$priv_key" > "$export_file"
            chmod 600 "$export_file"
            
            log "SSH key exported to $export_file"
            dialog_info "Key Exported" "The private key has been exported to:\n\n$export_file\n\nRemember to keep this file secure and delete it after transferring it to your client."
            ;;
          qr)
            # Generate QR code
            # Check if qrencode is installed
            if ! command -v qrencode &> /dev/null; then
              if dialog_confirm "Install QRencode" "qrencode is not installed. Would you like to install it?"; then
                apt update
                apt install -y qrencode
                track_installed_package "qrencode"
                log "qrencode installed"
              else
                dialog_info "QR Code" "qrencode is required for QR code generation."
                log "qrencode installation cancelled"
                continue
              fi
            fi
            
            # Create temporary file for QR code
            local qr_file="/tmp/sshkey_qr.png"
            qrencode -o "$qr_file" "$priv_key"
            
            # Display QR code (this is tricky in a terminal-based UI)
            dialog_info "QR Code" "QR code generated at $qr_file.\n\nPlease use a file browser or image viewer to view and scan it.\n\nRemember to delete the file when you're done for security reasons."
            ;;
        esac
        ;;
      rotate)
        # SSH key rotation (replace)
        local key_files=$(find "$ssh_dir" -name "id_*" -not -name "*.pub" 2>/dev/null)
        local key_options=()
        local key_counter=0
        
        for key_file in $key_files; do
          local key_type=$(basename "$key_file" | sed 's/^id_//')
          key_options+=("$key_counter" "$key_type key ($key_file)")
          key_counter=$((key_counter + 1))
        done
        
        if [ $key_counter -eq 0 ]; then
          dialog_info "No Keys" "No SSH keys found to rotate."
          continue
        fi
        
        local key_selection=$(dialog_menu "Select Key" "Select the key to rotate:" "${key_options[@]}")
        
        if [ -z "$key_selection" ]; then
          log "Key selection cancelled"
          continue
        fi
        
        local selected_key=$(echo "$key_files" | sed -n "$((key_selection + 1))p")
        local key_type=$(basename "$selected_key" | sed 's/^id_//')
        
        if dialog_confirm "Rotate Key" "Are you sure you want to rotate the $key_type key (replace with a new one)?"; then
          # Backup directory
          local backup_dir="$ssh_dir/backup"
          mkdir -p "$backup_dir"
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/ssh_keys/$user"
          
          # Back up current keys
          cp "$selected_key" "$backup_dir/id_${key_type}.$(date +%Y%m%d%H%M%S)"
          cp "$selected_key.pub" "$backup_dir/id_${key_type}.pub.$(date +%Y%m%d%H%M%S)"
          
          # Also backup to our main backup directory
          cp "$selected_key" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.backup.$(date +%Y%m%d%H%M%S)"
          cp "$selected_key.pub" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.backup.$(date +%Y%m%d%H%M%S)"
          
          # Remove current key from authorized_keys
          local current_pubkey=$(cat "$selected_key.pub")
          local temp_file=$(mktemp)
          grep -v "$current_pubkey" "$auth_keys" > "$temp_file" || true
          mv "$temp_file" "$auth_keys"
          
          # Generate new key
          local key_comment=$(dialog_input "Key Comment" "Enter a comment for the new key:" "$user@$(hostname)")
          
          if [ "$key_type" = "rsa" ]; then
            sudo -u $user ssh-keygen -t rsa -b 4096 -f "$selected_key" -N "" -C "$key_comment"
          elif [ "$key_type" = "ed25519" ]; then
            sudo -u $user ssh-keygen -t ed25519 -a 100 -f "$selected_key" -N "" -C "$key_comment"
          else
            sudo -u $user ssh-keygen -t $key_type -f "$selected_key" -N "" -C "$key_comment"
          fi
          
          # Add new public key to authorized_keys
          cat "$selected_key.pub" >> "$auth_keys"
          chmod 600 "$auth_keys"
          chown $user:$user "$auth_keys"
          
          # Copy new keys to backup directory
          cp "$selected_key" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.new.$(date +%Y%m%d%H%M%S)"
          cp "$selected_key.pub" "$BACKUP_DIR/ssh_keys/$user/id_${key_type}.pub.new.$(date +%Y%m%d%H%M%S)"
          
          log "SSH $key_type key rotated for $user"
          dialog_info "Key Rotated" "SSH $key_type key has been rotated (replaced).\n\nThe old key has been backed up in $backup_dir\n\nDon't forget to share the new public key with other servers where you need access."
          
          # Show new public key
          local new_pubkey=$(cat "$selected_key.pub")
          dialog_info "New Public Key" "New public key ($key_type):\n\n$new_pubkey"
          
          # Show new private key
          local new_privkey=$(cat "$selected_key")
          dialog_info "New Private Key" "New private key ($key_type):\n\nKEEP THIS KEY SAFE AND NEVER SHARE IT!\n\n$new_privkey"
        else
          log "Key rotation cancelled"
        fi
        ;;
      back|"")
        log "SSH key management exited"
        return
        ;;
    esac
  done
}

# Function for SSH banner configuration
configure_ssh_banner() {
  log "SSH banner configuration started"
  
  local banner_file="/etc/issue.net"
  local current_banner=""
  
  # Check if the banner file exists
  if [ -f "$banner_file" ]; then
    current_banner=$(cat "$banner_file")
  fi
  
  # Show current banner if present
  if [ ! -z "$current_banner" ]; then
    dialog_info "Current SSH Banner" "Current SSH login banner:\n\n$current_banner"
  fi
  
  # Options for banner configuration
  local action=$(dialog_menu "SSH Banner" "What do you want to do with the SSH banner?" \
    "edit" "Create/edit custom banner" \
    "template" "Use a banner template" \
    "disable" "Disable SSH banner" \
    "back" "Back")
  
  case $action in
    edit)
      # Create a temporary file with the current banner
      local temp_file=$(mktemp)
      echo "$current_banner" > "$temp_file"
      
      # Check if nano is installed
      if [ -z "$(which nano 2>/dev/null)" ]; then
        apt update && apt install -y nano
        track_installed_package "nano"
      fi
      
      # Show information message
      dialog_info "Edit Banner" "The text editor will now open to edit the SSH banner.\n\nPress Ctrl+X to save and exit when you're done."
      
      # Open editor
      nano "$temp_file"
      
      # Create backup directory
      mkdir -p "$BACKUP_DIR/ssh"
      
      # Back up existing banner if it exists
      if [ -f "$banner_file" ]; then
        cp "$banner_file" "$BACKUP_DIR/ssh/issue.net.backup.$(date +%Y%m%d%H%M%S)"
      fi
      
      # Read new banner and save
      local new_banner=$(cat "$temp_file")
      echo "$new_banner" > "$banner_file"
      rm -f "$temp_file"
      
      log "SSH banner customized"
      
      # Enable banner in SSH configuration
      if ! grep -q "^Banner" /etc/ssh/sshd_config; then
        echo "Banner $banner_file" >> /etc/ssh/sshd_config
      else
        sed -i "s|^Banner.*|Banner $banner_file|" /etc/ssh/sshd_config
      fi
      
      # Restart SSH service
      systemctl restart ssh
      
      dialog_info "Banner Updated" "The SSH banner has been updated and enabled."
      ;;
    template)
      # Templates menu
      local template=$(dialog_menu "Banner Template" "Choose a banner template:" \
        "legal" "Legal warning" \
        "monitor" "Monitoring/audit warning" \
        "welcome" "Welcome message" \
        "company" "Company banner")
      
      if [ -z "$template" ]; then
        log "Template selection cancelled"
        return
      fi
      
      local banner_content=""
case $template in
    legal)
      banner_content="*******************************************************************************
*                                                                             *
*                            LEGAL WARNING                                    *
*                                                                             *
* This system is restricted to authorized users for legitimate business       *
* purposes only. Unauthorized access is prohibited and may be punishable      *
* under the Computer Fraud and Abuse Act of 1986 and other laws.             *
*                                                                             *
* All activities on this system are logged, monitored, and subject to audit.  *
* By accessing this system, you consent to monitoring of system access and    *
* activities. Anyone using this system expressly consents to such monitoring. *
*                                                                             *
* If you are not an authorized user, DISCONNECT IMMEDIATELY.                  *
*                                                                             *
*******************************************************************************"
      ;;
    monitor)
      banner_content="*******************************************************************************
*                                                                             *
*                        SYSTEM MONITORING NOTICE                             *
*                                                                             *
* This system is monitored to ensure security, optimal performance, and       *
* appropriate use. Your activities may be monitored and recorded.             *
*                                                                             *
* Log data may be used for security incident response, troubleshooting,       *
* and compliance auditing purposes.                                           *
*                                                                             *
* Unauthorized access or use of this system is strictly prohibited.           *
*                                                                             *
*******************************************************************************"
      ;;
    welcome)
      banner_content="*******************************************************************************
*                                                                             *
*                               WELCOME                                       *
*                                                                             *
* Welcome to the system. This server is maintained by the IT department.      *
*                                                                             *
* Please report any issues or security concerns to: admin@example.com         *
* Support available: Monday-Friday, 8:00 AM - 5:00 PM                         *
*                                                                             *
* Remember to log out when you're finished with your session!                 *
*                                                                             *
*******************************************************************************"
      ;;
    company)
      banner_content="*******************************************************************************
*                                                                             *
*                         COMPANY SERVER                                      *
*                                                                             *
* This is a private computer system owned by COMPANY NAME.                    *
* It is for authorized use only.                                              *
*                                                                             *
* By using this IT system, you acknowledge and consent to the                 *
* company's policies regarding acceptable use and privacy.                    *
*                                                                             *
* For assistance, contact the IT Support team:                                *
* Phone: XXX-XXX-XXXX  Email: support@company.com                             *
*                                                                             *
*******************************************************************************"
      ;;
  esac
      
  # Create backup directory
  mkdir -p "$BACKUP_DIR/ssh"
  
  # Back up existing banner if it exists
  if [ -f "$banner_file" ]; then
    cp "$banner_file" "$BACKUP_DIR/ssh/issue.net.backup.$(date +%Y%m%d%H%M%S)"
  fi
  
  # Let the user customize template variables
  if [ "$template" = "company" ]; then
    local company_name=$(dialog_input "Company Name" "Enter your company name:" "COMPANY NAME")
    local support_phone=$(dialog_input "Support Phone" "Enter your support phone number:" "XXX-XXX-XXXX")
    local support_email=$(dialog_input "Support Email" "Enter your support email address:" "support@company.com")
    
    # Replace the placeholders with actual values
    banner_content=${banner_content//COMPANY NAME/$company_name}
    banner_content=${banner_content//XXX-XXX-XXXX/$support_phone}
    banner_content=${banner_content//support@company.com/$support_email}
  elif [ "$template" = "welcome" ]; then
    local support_email=$(dialog_input "Support Email" "Enter your support email address:" "admin@example.com")
    local support_hours=$(dialog_input "Support Hours" "Enter your support hours:" "Monday-Friday, 8:00 AM - 5:00 PM")
    
    # Replace the placeholders with actual values
    banner_content=${banner_content//admin@example.com/$support_email}
    banner_content=${banner_content//Monday-Friday, 8:00 AM - 5:00 PM/$support_hours}
  fi
  
  # Save the banner
  echo "$banner_content" > "$banner_file"
  log "SSH banner template ($template) applied"
  
  # Enable banner in SSH configuration
  if ! grep -q "^Banner" /etc/ssh/sshd_config; then
    echo "Banner $banner_file" >> /etc/ssh/sshd_config
  else
    sed -i "s|^Banner.*|Banner $banner_file|" /etc/ssh/sshd_config
  fi
  
  # Restart SSH service
  systemctl restart ssh
  
  dialog_info "Banner Template Applied" "The $template SSH banner has been applied and enabled."
  ;;
disable)
  # Disable banner
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR/ssh"
  
  # Back up existing banner if it exists
  if [ -f "$banner_file" ]; then
    cp "$banner_file" "$BACKUP_DIR/ssh/issue.net.backup.$(date +%Y%m%d%H%M%S)"
  fi
  
  # Disable banner in SSH configuration
  if grep -q "^Banner" /etc/ssh/sshd_config; then
    sed -i "s|^Banner.*|#Banner $banner_file|" /etc/ssh/sshd_config
  fi
  
  # Restart SSH service
  systemctl restart ssh
  
  log "SSH banner disabled"
  dialog_info "Banner Disabled" "The SSH banner has been disabled."
  ;;
back|"")
  log "SSH banner configuration cancelled"
  return
  ;;
  esac
}

# Function for SSH management main menu
ssh_management() {
  log "SSH management started"
  
  while true; do
    local action=$(dialog_menu "SSH Management" "Choose an option:" \
      "secure" "Secure OpenSSH configuration" \
      "keys" "SSH key management" \
      "banner" "Configure SSH banner" \
      "view" "View SSH configuration" \
      "logs" "View SSH logs" \
      "back" "Back to main menu")
    
    case $action in
      secure)
        secure_ssh
        ;;
      keys)
        manage_ssh_keys
        ;;
      banner)
        configure_ssh_banner
        ;;
      view)
        # View SSH configuration
        if [ -f "/etc/ssh/sshd_config" ]; then
          local ssh_config=$(cat /etc/ssh/sshd_config)
          dialog_info "SSH Configuration" "$ssh_config"
        else
          dialog_info "SSH Configuration" "SSH configuration file not found."
        fi
        ;;
      logs)
        # View SSH logs
        if [ -f "/var/log/auth.log" ]; then
          local log_lines=$(dialog_input "Log Lines" "Enter the number of SSH log lines to view:" "50")
          
          if [ -z "$log_lines" ]; then
            log_lines="50"
          fi
          
          local ssh_logs=$(grep "sshd" /var/log/auth.log | tail -n "$log_lines")
          dialog_info "SSH Logs" "Last $log_lines SSH log entries:\n\n$ssh_logs"
        else
          dialog_info "SSH Logs" "SSH log file not found."
        fi
        ;;
      back|"")
        log "SSH management exited"
        return
        ;;
    esac
  done
}

#######################################
# FIREWALL FUNCTIONS
#######################################

# Function for UFW (Uncomplicated Firewall) management
manage_ufw() {
  log "UFW management started"
  
  # Check if UFW is installed
  if ! command -v ufw &> /dev/null; then
    if dialog_confirm "Install UFW" "UFW (Uncomplicated Firewall) is not installed. Would you like to install it?"; then
      apt update
      apt install -y ufw
      track_installed_package "ufw"
      log "UFW installed"
    else
      dialog_info "UFW" "UFW is required for this configuration."
      log "UFW installation cancelled"
      return
    fi
  fi
  
  # Get current status
  local is_enabled=$(ufw status | grep -c "Status: active")
  
  # Dialog for UFW status
  local status_display="UFW status: "
  if [ $is_enabled -eq 1 ]; then
    status_display+="ENABLED"
  else
    status_display+="DISABLED"
  fi
  
  # Get current rules
  local current_rules=$(ufw status numbered)
  
  # Main UFW menu
  local ufw_option=$(dialog_menu "UFW Firewall" "$status_display\n\nChoose an option:" \
    "toggle" "Enable/Disable UFW" \
    "rules" "Manage firewall rules" \
    "preset" "Apply firewall presets" \
    "apps" "Manage application profiles" \
    "status" "Show detailed status" \
    "backup" "Backup/Restore firewall rules" \
    "reset" "Reset firewall to defaults" \
    "back" "Back to firewall menu")
  
  if [ -z "$ufw_option" ] || [ "$ufw_option" = "back" ]; then
    log "UFW management cancelled"
    return
  fi
  
  case $ufw_option in
    toggle)
      if [ $is_enabled -eq 1 ]; then
        # Disable UFW
        if dialog_confirm "Disable Firewall" "Are you sure you want to disable the firewall?\n\nThis will leave your system unprotected from unauthorized access."; then
          ufw disable
          log "UFW disabled"
          dialog_info "UFW Disabled" "The firewall has been disabled."
        else
          log "UFW disable cancelled"
        fi
      else
        # Enable UFW
        if dialog_confirm "Enable Firewall" "Do you want to enable the firewall?\n\nThis will enforce the firewall rules and may block unauthorized access."; then
          # First, ensure SSH access is allowed
          if dialog_confirm "Allow SSH" "Do you want to allow SSH access (recommended)?"; then
            local ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
            if [ -z "$ssh_port" ]; then
              ssh_port="22"
            fi
            
            ufw allow $ssh_port/tcp
            log "UFW rule added: allow SSH on port $ssh_port/tcp"
          fi
          
          ufw --force enable
          log "UFW enabled"
          dialog_info "UFW Enabled" "The firewall has been enabled with the current rules."
        else
          log "UFW enable cancelled"
        fi
      fi
      ;;
    rules)
      # Manage firewall rules
      local rule_action=$(dialog_menu "Manage UFW Rules" "Choose an action:" \
        "list" "List all rules" \
        "add" "Add a new rule" \
        "delete" "Delete a rule" \
        "change" "Change rule order" \
        "back" "Back to UFW menu")
      
      if [ -z "$rule_action" ] || [ "$rule_action" = "back" ]; then
        log "UFW rule management cancelled"
        return
      fi
      
      case $rule_action in
        list)
          # List all rules
          local rules=$(ufw status verbose)
          dialog_info "UFW Rules" "$rules"
          ;;
        add)
          # Add a new rule
          local rule_type=$(dialog_menu "Rule Type" "Choose the type of rule:" \
            "simple" "Allow/deny specific port" \
            "service" "Allow/deny common service" \
            "app" "Allow/deny application profile" \
            "advanced" "Advanced rule configuration" \
            "back" "Back")
          
          if [ -z "$rule_type" ] || [ "$rule_type" = "back" ]; then
            log "Rule type selection cancelled"
            return
          fi
          
          case $rule_type in
            simple)
              # Simple rule (port)
              local action=$(dialog_menu "Rule Action" "Select an action:" \
                "allow" "Allow traffic" \
                "deny" "Deny traffic" \
                "reject" "Reject traffic with response" \
                "back" "Back")
              
              if [ -z "$action" ] || [ "$action" = "back" ]; then
                log "Rule action selection cancelled"
                return
              fi
              
              local port=$(dialog_input "Port Number" "Enter the port number:" "")
              
              if [ -z "$port" ]; then
                log "Port input cancelled"
                return
              fi
              
              local protocol=$(dialog_menu "Protocol" "Select the protocol:" \
                "tcp" "TCP" \
                "udp" "UDP" \
                "both" "Both TCP and UDP" \
                "back" "Back")
              
              if [ -z "$protocol" ] || [ "$protocol" = "back" ]; then
                log "Protocol selection cancelled"
                return
              fi
              
              local direction=$(dialog_menu "Direction" "Select the direction:" \
                "in" "Incoming" \
                "out" "Outgoing" \
                "both" "Both incoming and outgoing" \
                "back" "Back")
              
              if [ -z "$direction" ] || [ "$direction" = "back" ]; then
                log "Direction selection cancelled"
                return
              fi
              
              # Construct and execute the UFW command
              local ufw_cmd="ufw $action"
              
              if [ "$direction" = "in" ]; then
                ufw_cmd+=" in"
              elif [ "$direction" = "out" ]; then
                ufw_cmd+=" out"
              fi
              
              if [ "$protocol" = "tcp" ]; then
                ufw_cmd+=" $port/tcp"
              elif [ "$protocol" = "udp" ]; then
                ufw_cmd+=" $port/udp"
              elif [ "$protocol" = "both" ]; then
                eval "$ufw_cmd $port/tcp"
                ufw_cmd+=" $port/udp"
              fi
              
              eval "$ufw_cmd"
              log "UFW rule added: $ufw_cmd"
              dialog_info "Rule Added" "The firewall rule has been added."
              ;;
            service)
              # Common service rule
              local action=$(dialog_menu "Rule Action" "Select an action:" \
                "allow" "Allow traffic" \
                "deny" "Deny traffic" \
                "reject" "Reject traffic with response" \
                "back" "Back")
              
              if [ -z "$action" ] || [ "$action" = "back" ]; then
                log "Rule action selection cancelled"
                return
              fi
              
              local service=$(dialog_menu "Service" "Select a service:" \
                "ssh" "SSH (port 22)" \
                "http" "HTTP (port 80)" \
                "https" "HTTPS (port 443)" \
                "ftp" "FTP (port 21)" \
                "mail" "Mail (SMTP/POP3/IMAP)" \
                "dns" "DNS (port 53)" \
                "back" "Back")
              
              if [ -z "$service" ] || [ "$service" = "back" ]; then
                log "Service selection cancelled"
                return
              fi
              
              # Construct and execute the UFW command
              local ufw_cmd="ufw $action"
              
              case $service in
                ssh)
                  ufw_cmd+=" 22/tcp"
                  ;;
                http)
                  ufw_cmd+=" 80/tcp"
                  ;;
                https)
                  ufw_cmd+=" 443/tcp"
                  ;;
                ftp)
                  ufw_cmd+=" 21/tcp"
                  ;;
                mail)
                  eval "$ufw_cmd 25/tcp"
                  eval "$ufw_cmd 110/tcp"
                  eval "$ufw_cmd 143/tcp"
                  eval "$ufw_cmd 587/tcp"
                  eval "$ufw_cmd 993/tcp"
                  eval "$ufw_cmd 995/tcp"
                  log "UFW mail rules added"
                  dialog_info "Rules Added" "The mail service firewall rules have been added."
                  return
                  ;;
                dns)
                  eval "$ufw_cmd 53/tcp"
                  ufw_cmd+=" 53/udp"
                  ;;
              esac
              
              eval "$ufw_cmd"
              log "UFW rule added: $ufw_cmd"
              dialog_info "Rule Added" "The $service firewall rule has been added."
              ;;
            app)
              # Application profile rule
              local action=$(dialog_menu "Rule Action" "Select an action:" \
                "allow" "Allow traffic" \
                "deny" "Deny traffic" \
                "reject" "Reject traffic with response" \
                "back" "Back")
              
              if [ -z "$action" ] || [ "$action" = "back" ]; then
                log "Rule action selection cancelled"
                return
              fi
              
              # Get available application profiles
              local available_apps=$(ufw app list | tail -n +2 | awk '{print $1}')
              
              if [ -z "$available_apps" ]; then
                dialog_info "No Profiles" "No application profiles found."
                log "No application profiles found"
                return
              fi
              
              # Build menu options
              local app_options=()
              while read -r app; do
                app_options+=("$app" "Application profile")
              done <<< "$available_apps"
              
              # Let user choose an application
              local selected_app=$(dialog_menu "Select Application" "Choose an application profile:" "${app_options[@]}")
              
              if [ -z "$selected_app" ]; then
                log "Application selection cancelled"
                return
              fi
              
              # Add the rule
              ufw $action app "$selected_app"
              log "UFW rule added: $action app $selected_app"
              dialog_info "Rule Added" "The rule for $selected_app has been added."
              ;;
            advanced)
              # Advanced rule configuration
              local rule_spec=$(dialog_input "Advanced Rule" "Enter the full UFW rule specification:\n(e.g., 'allow from 192.168.1.0/24 to any port 22')" "")
              
              if [ -z "$rule_spec" ]; then
                log "Advanced rule input cancelled"
                return
              fi
              
              # Add the rule
              ufw $rule_spec
              log "UFW advanced rule added: $rule_spec"
              dialog_info "Rule Added" "The advanced rule has been added."
              ;;
          esac
          ;;
        delete)
          # Delete a rule
          local rules=$(ufw status numbered)
          
          if ! echo "$rules" | grep -q "^[[0-9]"; then
            dialog_info "No Rules" "No numbered rules found to delete."
            log "No numbered rules found"
            return
          fi
          
          dialog_info "Current Rules" "$rules"
          
          local rule_number=$(dialog_input "Delete Rule" "Enter the number of the rule to delete:" "")
          
          if [ -z "$rule_number" ]; then
            log "Rule number input cancelled"
            return
          fi
          
          if ! [[ "$rule_number" =~ ^[0-9]+$ ]]; then
            dialog_info "Invalid Number" "Please enter a valid rule number."
            log "Invalid rule number: $rule_number"
            return
          fi
          
          if dialog_confirm "Delete Rule" "Are you sure you want to delete rule #$rule_number?"; then
            ufw --force delete $rule_number
            log "UFW rule #$rule_number deleted"
            dialog_info "Rule Deleted" "Rule #$rule_number has been deleted."
          else
            log "Rule deletion cancelled"
          fi
          ;;
        change)
          # Change rule order (not natively supported by UFW)
          dialog_info "Rule Order" "Changing rule order is not directly supported by UFW.\n\nYou need to delete rules and add them again in the desired order."
          ;;
      esac
      ;;
    preset)
      # Apply firewall presets
      local preset_action=$(dialog_menu "Firewall Presets" "Choose a preset to apply:" \
        "basic" "Basic server (SSH, HTTP, HTTPS)" \
        "secure" "Secure server (SSH only)" \
        "web" "Web server (HTTP, HTTPS, FTP)" \
        "mail" "Mail server" \
        "db" "Database server" \
        "back" "Back to UFW menu")
      
      if [ -z "$preset_action" ] || [ "$preset_action" = "back" ]; then
        log "Preset selection cancelled"
        return
      fi
      
      # Create backup first
      mkdir -p "$BACKUP_DIR/firewall"
      ufw status verbose > "$BACKUP_DIR/firewall/ufw_before_preset_$(date +%Y%m%d%H%M%S).txt"
      
      # Ask for confirmation
      if ! dialog_confirm "Apply Preset" "This will reset your current UFW configuration and apply the $preset_action preset.\n\nDo you want to continue?"; then
        log "Preset application cancelled"
        return
      fi
      
      # Reset UFW
      ufw --force reset
      
      # Apply the selected preset
      case $preset_action in
        basic)
          # Allow SSH, HTTP, HTTPS
          ufw allow ssh
          ufw allow http
          ufw allow https
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          log "Basic server preset applied"
          dialog_info "Preset Applied" "Basic server preset has been applied.\n\nAllowed traffic:\n- SSH\n- HTTP\n- HTTPS"
          ;;
        secure)
          # Allow SSH only
          ufw allow ssh
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          log "Secure server preset applied"
          dialog_info "Preset Applied" "Secure server preset has been applied.\n\nAllowed traffic:\n- SSH only"
          ;;
        web)
          # Web server (HTTP, HTTPS, FTP)
          ufw allow ssh
          ufw allow http
          ufw allow https
          ufw allow ftp
          ufw allow 21/tcp
          ufw allow 20/tcp
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          log "Web server preset applied"
          dialog_info "Preset Applied" "Web server preset has been applied.\n\nAllowed traffic:\n- SSH\n- HTTP\n- HTTPS\n- FTP"
          ;;
        mail)
          # Mail server
          ufw allow ssh
          ufw allow smtp
          ufw allow 25/tcp
          ufw allow 465/tcp
          ufw allow 587/tcp
          ufw allow 110/tcp
          ufw allow 995/tcp
          ufw allow 143/tcp
          ufw allow 993/tcp
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          log "Mail server preset applied"
          dialog_info "Preset Applied" "Mail server preset has been applied.\n\nAllowed traffic:\n- SSH\n- SMTP (25/tcp, 465/tcp, 587/tcp)\n- POP3 (110/tcp, 995/tcp)\n- IMAP (143/tcp, 993/tcp)"
          ;;
        db)
          # Database server
          ufw allow ssh
          ufw allow 3306/tcp # MySQL
          ufw allow 5432/tcp # PostgreSQL
          ufw allow 27017/tcp # MongoDB
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          log "Database server preset applied"
          dialog_info "Preset Applied" "Database server preset has been applied.\n\nAllowed traffic:\n- SSH\n- MySQL (3306/tcp)\n- PostgreSQL (5432/tcp)\n- MongoDB (27017/tcp)"
          ;;
      esac
      ;;
    apps)
      # Manage application profiles
      local app_action=$(dialog_menu "Application Profiles" "Choose an action:" \
        "list" "List available application profiles" \
        "info" "Show application profile details" \
        "back" "Back to UFW menu")
      
      if [ -z "$app_action" ] || [ "$app_action" = "back" ]; then
        log "Application profile management cancelled"
        return
      fi
      
      case $app_action in
        list)
          # List available application profiles
          local app_list=$(ufw app list)
          dialog_info "Application Profiles" "$app_list"
          ;;
        info)
          # Show application profile details
          
          # Get available application profiles
          local available_apps=$(ufw app list | tail -n +2 | awk '{print $1}')
          
          if [ -z "$available_apps" ]; then
            dialog_info "No Profiles" "No application profiles found."
            log "No application profiles found"
            return
          fi
          
          # Build menu options
          local app_options=()
          while read -r app; do
            app_options+=("$app" "Application profile")
          done <<< "$available_apps"
          
          # Let user choose an application
          local selected_app=$(dialog_menu "Select Application" "Choose an application profile:" "${app_options[@]}")
          
          if [ -z "$selected_app" ]; then
            log "Application selection cancelled"
            return
          fi
          
          # Show profile details
          local app_info=$(ufw app info "$selected_app")
          dialog_info "Profile: $selected_app" "$app_info"
          ;;
      esac
      ;;
    status)
      # Show detailed status
      local status_output=$(ufw status verbose)
      dialog_info "UFW Status" "$status_output"
      ;;
    backup)
      # Backup/Restore firewall rules
      local backup_action=$(dialog_menu "Backup/Restore" "Choose an action:" \
        "backup" "Backup current firewall rules" \
        "restore" "Restore firewall rules from backup" \
        "back" "Back to UFW menu")
      
      if [ -z "$backup_action" ] || [ "$backup_action" = "back" ]; then
        log "Backup/restore cancelled"
        return
      fi
      
      case $backup_action in
        backup)
          # Backup current firewall rules
          local backup_dir="$BACKUP_DIR/firewall"
          mkdir -p "$backup_dir"
          
          local backup_file="$backup_dir/ufw_backup_$(date +%Y%m%d%H%M%S).rules"
          
          # Create the backup
          ufw status verbose > "$backup_file"
          cp /etc/ufw/user.rules "$backup_file.conf"
          
          log "UFW configuration backed up to $backup_file"
          dialog_info "Backup Created" "The UFW configuration has been backed up to:\n\n$backup_file\n$backup_file.conf"
          ;;
        restore)
          # Restore firewall rules from backup
          local backup_dir="$BACKUP_DIR/firewall"
          
          if [ ! -d "$backup_dir" ]; then
            dialog_info "No Backups" "No backup directory found."
            log "No UFW backup directory found"
            return
          fi
          
          # Find .conf backup files
          local backup_files=$(find "$backup_dir" -name "*.rules.conf" -type f | sort -r)
          
          if [ -z "$backup_files" ]; then
            dialog_info "No Backups" "No UFW configuration backup files found."
            log "No UFW backup files found"
            return
          fi
          
          # Build menu options
          local backup_options=()
          local counter=0
          
while read -r backup_file; do
            local backup_date=$(basename "$backup_file" | sed 's/ufw_backup_\(.*\)\.rules\.conf/\1/')
            backup_date=$(date -d "${backup_date:0:8} ${backup_date:8:2}:${backup_date:10:2}:${backup_date:12:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$backup_date")
            backup_options+=("$backup_file" "Backup from $backup_date")
            counter=$((counter + 1))
          done <<< "$backup_files"
          
          # Let user choose a backup file
          local selected_backup=$(dialog_menu "Select Backup" "Choose a backup to restore:" "${backup_options[@]}")
          
          if [ -z "$selected_backup" ]; then
            log "Backup selection cancelled"
            return
          fi
          
          # Ask for confirmation
          if ! dialog_confirm "Restore Backup" "Are you sure you want to restore the UFW configuration from this backup?\n\nThis will overwrite your current firewall rules."; then
            log "Backup restoration cancelled"
            return
          fi
          
          # Disable UFW first
          ufw --force disable
          
          # Restore the rules
          cp "$selected_backup" /etc/ufw/user.rules
          
          # Reload and enable UFW
          ufw --force reset
          ufw --force enable
          
          log "UFW configuration restored from $selected_backup"
          dialog_info "Backup Restored" "The UFW configuration has been restored from the selected backup."
          ;;
      esac
      ;;
    reset)
      # Reset firewall to defaults
      if dialog_confirm "Reset Firewall" "Are you sure you want to reset the firewall to default settings?\n\nThis will remove all custom rules."; then
        # Create backup first
        mkdir -p "$BACKUP_DIR/firewall"
        ufw status verbose > "$BACKUP_DIR/firewall/ufw_before_reset_$(date +%Y%m%d%H%M%S).txt"
        
        # Reset UFW
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH (important to prevent lockout)
        if dialog_confirm "Allow SSH" "Do you want to allow SSH connections (recommended)?"; then
          ufw allow ssh
        fi
        
        # Enable UFW
        ufw --force enable
        
        log "UFW reset to defaults"
        dialog_info "Firewall Reset" "The firewall has been reset to default settings."
      else
        log "UFW reset cancelled"
      fi
      ;;
  esac
}

# Function for Advanced Firewall Configuration
configure_advanced_firewall() {
  log "Advanced firewall configuration started"
  
  # Menu for advanced firewall options
  local fw_option=$(dialog_menu "Advanced Firewall" "Choose an option:" \
    "iptables" "Configure iptables directly" \
    "geoip" "Block traffic by country" \
    "fail2ban" "Configure Fail2Ban for intrusion prevention" \
    "rate" "Implement rate limiting" \
    "logs" "View and analyze firewall logs" \
    "script" "Create custom firewall script" \
    "back" "Back to firewall menu")
  
  if [ -z "$fw_option" ] || [ "$fw_option" = "back" ]; then
    log "Advanced firewall configuration cancelled"
    return
  fi
  
  case $fw_option in
    iptables)
      # Configure iptables directly
      # Check if iptables is installed
      if ! command -v iptables &> /dev/null; then
        if dialog_confirm "Install iptables" "iptables is not installed. Would you like to install it?"; then
          apt update
          apt install -y iptables
          track_installed_package "iptables"
          log "iptables installed"
        else
          dialog_info "iptables" "iptables is required for this configuration."
          log "iptables installation cancelled"
          return
        fi
      fi
      
      # iptables options
      local iptables_option=$(dialog_menu "iptables Configuration" "Choose an option:" \
        "view" "View current iptables rules" \
        "save" "Save current iptables rules" \
        "restore" "Restore saved iptables rules" \
        "add" "Add a custom iptables rule" \
        "flush" "Flush all iptables rules" \
        "back" "Back to advanced firewall menu")
      
      if [ -z "$iptables_option" ] || [ "$iptables_option" = "back" ]; then
        log "iptables option selection cancelled"
        return
      fi
      
      case $iptables_option in
        view)
          # View current iptables rules
          local iptables_rules=$(iptables -L -v --line-numbers)
          dialog_info "iptables Rules" "$iptables_rules"
          ;;
        save)
          # Save current iptables rules
          local backup_dir="$BACKUP_DIR/firewall"
          mkdir -p "$backup_dir"
          
          local backup_file="$backup_dir/iptables_backup_$(date +%Y%m%d%H%M%S).rules"
          
          # Create the backup
          iptables-save > "$backup_file"
          
          log "iptables rules backed up to $backup_file"
          dialog_info "Rules Saved" "The iptables rules have been saved to:\n\n$backup_file"
          ;;
        restore)
          # Restore saved iptables rules
          local backup_dir="$BACKUP_DIR/firewall"
          
          if [ ! -d "$backup_dir" ]; then
            dialog_info "No Backups" "No backup directory found."
            log "No iptables backup directory found"
            return
          fi
          
          # Find iptables backup files
          local backup_files=$(find "$backup_dir" -name "iptables_backup_*.rules" -type f | sort -r)
          
          if [ -z "$backup_files" ]; then
            dialog_info "No Backups" "No iptables backup files found."
            log "No iptables backup files found"
            return
          fi
          
          # Build menu options
          local backup_options=()
          local counter=0
          
          while read -r backup_file; do
            local backup_date=$(basename "$backup_file" | sed 's/iptables_backup_\(.*\)\.rules/\1/')
            backup_date=$(date -d "${backup_date:0:8} ${backup_date:8:2}:${backup_date:10:2}:${backup_date:12:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$backup_date")
            backup_options+=("$backup_file" "Backup from $backup_date")
            counter=$((counter + 1))
          done <<< "$backup_files"
          
          # Let user choose a backup file
          local selected_backup=$(dialog_menu "Select Backup" "Choose a backup to restore:" "${backup_options[@]}")
          
          if [ -z "$selected_backup" ]; then
            log "Backup selection cancelled"
            return
          fi
          
          # Ask for confirmation
          if ! dialog_confirm "Restore Backup" "Are you sure you want to restore the iptables rules from this backup?\n\nThis will overwrite your current firewall rules."; then
            log "Backup restoration cancelled"
            return
          fi
          
          # Restore the rules
          iptables-restore < "$selected_backup"
          
          log "iptables rules restored from $selected_backup"
          dialog_info "Backup Restored" "The iptables rules have been restored from the selected backup."
          ;;
        add)
          # Add a custom iptables rule
          local custom_rule=$(dialog_input "Custom Rule" "Enter the custom iptables rule (without the 'iptables' command):" "-A INPUT -p tcp --dport 22 -j ACCEPT")
          
          if [ -z "$custom_rule" ]; then
            log "Custom rule input cancelled"
            return
          fi
          
          # Execute the rule
          iptables $custom_rule
          
          log "Custom iptables rule added: $custom_rule"
          dialog_info "Rule Added" "The custom iptables rule has been added."
          ;;
        flush)
          # Flush all iptables rules
          if dialog_confirm "Flush Rules" "Are you sure you want to flush all iptables rules?\n\nThis will remove all firewall rules and may leave your system vulnerable."; then
            # Create backup first
            local backup_dir="$BACKUP_DIR/firewall"
            mkdir -p "$backup_dir"
            
            local backup_file="$backup_dir/iptables_before_flush_$(date +%Y%m%d%H%M%S).rules"
            
            # Create the backup
            iptables-save > "$backup_file"
            
            # Flush rules
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -t mangle -F
            iptables -t mangle -X
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            
            log "iptables rules flushed"
            dialog_info "Rules Flushed" "All iptables rules have been flushed."
          else
            log "iptables flush cancelled"
          fi
          ;;
      esac
      ;;
    geoip)
      # Block traffic by country
      # Check if xtables-addons is installed
      if ! command -v xt_geoip_build &> /dev/null; then
        if dialog_confirm "Install GeoIP Tools" "GeoIP tools for iptables are not installed. Would you like to install them?"; then
          apt update
          apt install -y xtables-addons-common libtext-csv-xs-perl iptables-persistent
          track_installed_package "xtables-addons-common"
          track_installed_package "libtext-csv-xs-perl"
          track_installed_package "iptables-persistent"
          log "GeoIP tools installed"
        else
          dialog_info "GeoIP Tools" "GeoIP tools are required for country-based filtering."
          log "GeoIP tools installation cancelled"
          return
        fi
      fi
      
      # GeoIP options
      local geoip_option=$(dialog_menu "GeoIP Configuration" "Choose an option:" \
        "download" "Download and update GeoIP database" \
        "block" "Block traffic from specific countries" \
        "view" "View currently blocked countries" \
        "unblock" "Unblock a country" \
        "back" "Back to advanced firewall menu")
      
      if [ -z "$geoip_option" ] || [ "$geoip_option" = "back" ]; then
        log "GeoIP option selection cancelled"
        return
      fi
      
      case $geoip_option in
        download)
          # Download and update GeoIP database
          if dialog_confirm "Download Database" "Do you want to download and update the GeoIP database?\n\nThis may take a few minutes."; then
            # Create directory
            mkdir -p /usr/share/xt_geoip
            
            # Download and build the database
            (
              echo "10"; echo "XXX"; echo "Downloading GeoIP database..."; echo "XXX"
              
              cd /tmp
              rm -f GeoIPCountryWhois.csv.gz
              wget -q http://download.maxmind.com/download/geoip/database/GeoIPCountryCSV.zip
              
              echo "30"; echo "XXX"; echo "Extracting GeoIP database..."; echo "XXX"
              
              unzip -o GeoIPCountryCSV.zip
              
              echo "50"; echo "XXX"; echo "Building GeoIP database..."; echo "XXX"
              
              mkdir -p /usr/share/xt_geoip
              /usr/lib/xtables-addons/xt_geoip_build -D /usr/share/xt_geoip GeoIPCountryWhois.csv
              
              echo "70"; echo "XXX"; echo "Loading GeoIP module..."; echo "XXX"
              
              modprobe xt_geoip
              
              echo "90"; echo "XXX"; echo "Cleaning up..."; echo "XXX"
              
              rm -f GeoIPCountryWhois.csv GeoIPCountryCSV.zip
              
              echo "100"; echo "XXX"; echo "GeoIP database updated."; echo "XXX"
              
            ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Updating GeoIP Database" --gauge "Please wait..." 10 70 0
            
            log "GeoIP database updated"
            dialog_info "Database Updated" "The GeoIP database has been downloaded and updated."
          else
            log "GeoIP database update cancelled"
          fi
          ;;
        block)
          # Block traffic from specific countries
          # List of countries
          local country_list=$(cat << 'EOL'
AF,Afghanistan
AL,Albania
DZ,Algeria
AS,American Samoa
AD,Andorra
AO,Angola
AI,Anguilla
AQ,Antarctica
AG,Antigua and Barbuda
AR,Argentina
AM,Armenia
AW,Aruba
AU,Australia
AT,Austria
AZ,Azerbaijan
BS,Bahamas
BH,Bahrain
BD,Bangladesh
BB,Barbados
BY,Belarus
BE,Belgium
BZ,Belize
BJ,Benin
BM,Bermuda
BT,Bhutan
BO,Bolivia
BA,Bosnia and Herzegovina
BW,Botswana
BV,Bouvet Island
BR,Brazil
IO,British Indian Ocean Territory
BN,Brunei Darussalam
BG,Bulgaria
BF,Burkina Faso
BI,Burundi
KH,Cambodia
CM,Cameroon
CA,Canada
CV,Cape Verde
KY,Cayman Islands
CF,Central African Republic
TD,Chad
CL,Chile
CN,China
CX,Christmas Island
CC,Cocos (Keeling) Islands
CO,Colombia
KM,Comoros
CG,Congo
CD,Congo, the Democratic Republic of the
CK,Cook Islands
CR,Costa Rica
CI,Cote D'Ivoire
HR,Croatia
CU,Cuba
CY,Cyprus
CZ,Czech Republic
DK,Denmark
DJ,Djibouti
DM,Dominica
DO,Dominican Republic
EC,Ecuador
EG,Egypt
SV,El Salvador
GQ,Equatorial Guinea
ER,Eritrea
EE,Estonia
ET,Ethiopia
FK,Falkland Islands (Malvinas)
FO,Faroe Islands
FJ,Fiji
FI,Finland
FR,France
GF,French Guiana
PF,French Polynesia
TF,French Southern Territories
GA,Gabon
GM,Gambia
GE,Georgia
DE,Germany
GH,Ghana
GI,Gibraltar
GR,Greece
GL,Greenland
GD,Grenada
GP,Guadeloupe
GU,Guam
GT,Guatemala
GN,Guinea
GW,Guinea-Bissau
GY,Guyana
HT,Haiti
HM,Heard Island and Mcdonald Islands
VA,Holy See (Vatican City State)
HN,Honduras
HK,Hong Kong
HU,Hungary
IS,Iceland
IN,India
ID,Indonesia
IR,Iran, Islamic Republic of
IQ,Iraq
IE,Ireland
IL,Israel
IT,Italy
JM,Jamaica
JP,Japan
JO,Jordan
KZ,Kazakhstan
KE,Kenya
KI,Kiribati
KP,Korea, Democratic People's Republic of
KR,Korea, Republic of
KW,Kuwait
KG,Kyrgyzstan
LA,Lao People's Democratic Republic
LV,Latvia
LB,Lebanon
LS,Lesotho
LR,Liberia
LY,Libyan Arab Jamahiriya
LI,Liechtenstein
LT,Lithuania
LU,Luxembourg
MO,Macao
MK,Macedonia, the Former Yugoslav Republic of
MG,Madagascar
MW,Malawi
MY,Malaysia
MV,Maldives
ML,Mali
MT,Malta
MH,Marshall Islands
MQ,Martinique
MR,Mauritania
MU,Mauritius
YT,Mayotte
MX,Mexico
FM,Micronesia, Federated States of
MD,Moldova, Republic of
MC,Monaco
MN,Mongolia
MS,Montserrat
MA,Morocco
MZ,Mozambique
MM,Myanmar
NA,Namibia
NR,Nauru
NP,Nepal
NL,Netherlands
NC,New Caledonia
NZ,New Zealand
NI,Nicaragua
NE,Niger
NG,Nigeria
NU,Niue
NF,Norfolk Island
MP,Northern Mariana Islands
NO,Norway
OM,Oman
PK,Pakistan
PW,Palau
PS,Palestinian Territory, Occupied
PA,Panama
PG,Papua New Guinea
PY,Paraguay
PE,Peru
PH,Philippines
PN,Pitcairn
PL,Poland
PT,Portugal
PR,Puerto Rico
QA,Qatar
RE,Reunion
RO,Romania
RU,Russian Federation
RW,Rwanda
SH,Saint Helena
KN,Saint Kitts and Nevis
LC,Saint Lucia
PM,Saint Pierre and Miquelon
VC,Saint Vincent and the Grenadines
WS,Samoa
SM,San Marino
ST,Sao Tome and Principe
SA,Saudi Arabia
SN,Senegal
CS,Serbia and Montenegro
SC,Seychelles
SL,Sierra Leone
SG,Singapore
SK,Slovakia
SI,Slovenia
SB,Solomon Islands
SO,Somalia
ZA,South Africa
GS,South Georgia and the South Sandwich Islands
ES,Spain
LK,Sri Lanka
SD,Sudan
SR,Suriname
SJ,Svalbard and Jan Mayen
SZ,Swaziland
SE,Sweden
CH,Switzerland
SY,Syrian Arab Republic
TW,Taiwan
TJ,Tajikistan
TZ,Tanzania, United Republic of
TH,Thailand
TL,Timor-Leste
TG,Togo
TK,Tokelau
TO,Tonga
TT,Trinidad and Tobago
TN,Tunisia
TR,Turkey
TM,Turkmenistan
TC,Turks and Caicos Islands
TV,Tuvalu
UG,Uganda
UA,Ukraine
AE,United Arab Emirates
GB,United Kingdom
US,United States
UM,United States Minor Outlying Islands
UY,Uruguay
UZ,Uzbekistan
VU,Vanuatu
VE,Venezuela
VN,Vietnam
VG,Virgin Islands, British
VI,Virgin Islands, U.S.
WF,Wallis and Futuna
EH,Western Sahara
YE,Yemen
ZM,Zambia
ZW,Zimbabwe
EOL
)

          # Create a temporary file for country codes
          local country_codes_file=$(mktemp)
          echo "$country_list" > "$country_codes_file"
          
          # Build options for country selection
          local country_options=()
          while IFS=',' read -r code name; do
            country_options+=("$code" "$name" "off")
          done < "$country_codes_file"
          
          # Let user select countries to block
          local selected_countries=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Block Countries" \
            --checklist "Select countries to block traffic from:" 20 60 15 \
            "${country_options[@]}" 3>&1 1>&2 2>&3)
          
          if [ -z "$selected_countries" ]; then
            log "Country selection cancelled"
            rm -f "$country_codes_file"
            return
          fi
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/firewall"
          
          # Backup current iptables rules
          iptables-save > "$BACKUP_DIR/firewall/iptables_before_geoip_$(date +%Y%m%d%H%M%S).rules"
          
          # Create geoip chain if it doesn't exist
          iptables -L GEOIP >/dev/null 2>&1 || iptables -N GEOIP
          
          # Clear existing rules in the chain
          iptables -F GEOIP
          
          # Add rules for selected countries
          for country in $selected_countries; do
            # Get country name for logging
            local country_name=$(grep "^$country," "$country_codes_file" | cut -d',' -f2)
            
            iptables -A GEOIP -m geoip --src-cc $country -j DROP
            log "Traffic from $country ($country_name) blocked"
          done
          
          # Make sure the chain is used
          iptables -C INPUT -j GEOIP >/dev/null 2>&1 || iptables -A INPUT -j GEOIP
          
          # Clean up
          rm -f "$country_codes_file"
          
          log "GeoIP blocking configured for selected countries"
          dialog_info "Countries Blocked" "Traffic from the selected countries has been blocked."
          ;;
        view)
          # View currently blocked countries
          local blocked_countries=$(iptables -L GEOIP -v | grep -oP '(?<=--src-cc )[A-Z]{2}' | sort)
          
          if [ -z "$blocked_countries" ]; then
            dialog_info "No Blocked Countries" "No countries are currently blocked."
            log "No blocked countries found"
            return
          fi
          
          # Format the output
          local blocked_list="Currently blocked countries:\n\n"
          
          for country in $blocked_countries; do
            local country_name=$(grep "^$country," <<< "$country_list" | cut -d',' -f2)
            blocked_list+="$country - $country_name\n"
          done
          
          dialog_info "Blocked Countries" "$blocked_list"
          ;;
        unblock)
          # Unblock a country
          local blocked_countries=$(iptables -L GEOIP -v | grep -oP '(?<=--src-cc )[A-Z]{2}' | sort)
          
          if [ -z "$blocked_countries" ]; then
            dialog_info "No Blocked Countries" "No countries are currently blocked."
            log "No blocked countries found"
            return
          fi
          
          # Build options for country selection
          local country_options=()
          
          for country in $blocked_countries; do
            local country_name=$(grep "^$country," <<< "$country_list" | cut -d',' -f2)
            country_options+=("$country" "$country_name")
          done
          
          # Let user select a country to unblock
          local selected_country=$(dialog_menu "Unblock Country" "Select a country to unblock:" "${country_options[@]}")
          
          if [ -z "$selected_country" ]; then
            log "Country unblock selection cancelled"
            return
          fi
          
          # Get country name for logging
          local country_name=$(grep "^$selected_country," <<< "$country_list" | cut -d',' -f2)
          
          # Remove the rule
          iptables -D GEOIP -m geoip --src-cc $selected_country -j DROP
          
          log "Traffic from $selected_country ($country_name) unblocked"
          dialog_info "Country Unblocked" "Traffic from $selected_country ($country_name) has been unblocked."
          ;;
      esac
      ;;
    fail2ban)
      # Configure Fail2Ban for intrusion prevention
      # Check if Fail2Ban is installed
      if ! command -v fail2ban-client &> /dev/null; then
        if dialog_confirm "Install Fail2Ban" "Fail2Ban is not installed. Would you like to install it?"; then
          apt update
          apt install -y fail2ban
          track_installed_package "fail2ban"
          log "Fail2Ban installed"
        else
          dialog_info "Fail2Ban" "Fail2Ban is required for this configuration."
          log "Fail2Ban installation cancelled"
          return
        fi
      fi
      
      # Fail2Ban options
      local fail2ban_option=$(dialog_menu "Fail2Ban Configuration" "Choose an option:" \
        "status" "View Fail2Ban status" \
        "jails" "Configure jails" \
        "actions" "Configure actions" \
        "ban" "Manually ban an IP address" \
        "unban" "Unban an IP address" \
        "logs" "View Fail2Ban logs" \
        "back" "Back to advanced firewall menu")
      
      if [ -z "$fail2ban_option" ] || [ "$fail2ban_option" = "back" ]; then
        log "Fail2Ban option selection cancelled"
        return
      fi
      
      case $fail2ban_option in
        status)
          # View Fail2Ban status
          local status_output=$(fail2ban-client status)
          local active_jails=$(fail2ban-client status | grep "Jail list" | sed 's/^.*: //')
          
          local status_info="$status_output\n\nActive jails: $active_jails\n\n"
          
          for jail in $(echo "$active_jails" | tr ',' ' '); do
            status_info+="==== $jail ====\n"
            status_info+="$(fail2ban-client status $jail)\n\n"
          done
          
          dialog_info "Fail2Ban Status" "$status_info"
          ;;
        jails)
          # Configure jails
          local jail_action=$(dialog_menu "Configure Jails" "Choose an action:" \
            "enable" "Enable a jail" \
            "disable" "Disable a jail" \
            "config" "Configure a jail" \
            "back" "Back to Fail2Ban menu")
          
          if [ -z "$jail_action" ] || [ "$jail_action" = "back" ]; then
            log "Jail action selection cancelled"
            return
          fi
          
          # Get available jails
          local available_jails=$(fail2ban-client -c /etc/fail2ban/fail2ban.conf -d | grep -P "\\['.*'\\]" | grep -oP "(?<=\\[').*(?='\\])" | sort)
          
          case $jail_action in
            enable)
              # Enable a jail
              local jail_options=()
              
              for jail in $available_jails; do
                jail_options+=("$jail" "Jail")
              done
              
              local selected_jail=$(dialog_menu "Enable Jail" "Select a jail to enable:" "${jail_options[@]}")
              
              if [ -z "$selected_jail" ]; then
                log "Jail selection cancelled"
                return
              fi
              
              # Create directory
              mkdir -p /etc/fail2ban/jail.d
              
              # Create configuration file
              cat > "/etc/fail2ban/jail.d/$selected_jail.conf" << EOL
[$selected_jail]
enabled = true
EOL
              
              # Restart Fail2Ban to apply changes
              systemctl restart fail2ban
              
              log "Fail2Ban jail $selected_jail enabled"
              dialog_info "Jail Enabled" "The $selected_jail jail has been enabled."
              ;;
            disable)
              # Disable a jail
              local active_jails=$(fail2ban-client status | grep "Jail list" | sed 's/^.*: //' | tr ',' ' ')
              
              if [ -z "$active_jails" ]; then
                dialog_info "No Active Jails" "No active jails found."
                log "No active jails found"
                return
              fi
              
              local jail_options=()
              
              for jail in $active_jails; do
                jail_options+=("$jail" "Active jail")
              done
              
              local selected_jail=$(dialog_menu "Disable Jail" "Select a jail to disable:" "${jail_options[@]}")
              
              if [ -z "$selected_jail" ]; then
                log "Jail selection cancelled"
                return
              fi
              
              # Create directory
              mkdir -p /etc/fail2ban/jail.d
              
              # Create configuration file
              cat > "/etc/fail2ban/jail.d/$selected_jail.conf" << EOL
[$selected_jail]
enabled = false
EOL
              
              # Restart Fail2Ban to apply changes
              systemctl restart fail2ban
              
              log "Fail2Ban jail $selected_jail disabled"
              dialog_info "Jail Disabled" "The $selected_jail jail has been disabled."
              ;;
            config)
              # Configure a jail
              local jail_options=()
              
              for jail in $available_jails; do
                jail_options+=("$jail" "Jail")
              done
              
              local selected_jail=$(dialog_menu "Configure Jail" "Select a jail to configure:" "${jail_options[@]}")
              
              if [ -z "$selected_jail" ]; then
                log "Jail selection cancelled"
                return
              fi
              
              # Ask for jail parameters
              local ban_time=$(dialog_input "Ban Time" "Enter the ban time in seconds (leave empty for default):" "3600")
              local find_time=$(dialog_input "Find Time" "Enter the find time in seconds (leave empty for default):" "600")
              local max_retry=$(dialog_input "Max Retry" "Enter the maximum number of retries (leave empty for default):" "5")
              
              # Create directory
              mkdir -p /etc/fail2ban/jail.d
              
              # Create configuration file
              cat > "/etc/fail2ban/jail.d/$selected_jail.conf" << EOL
[$selected_jail]
enabled = true
EOL
              
              if [ ! -z "$ban_time" ]; then
                echo "bantime = $ban_time" >> "/etc/fail2ban/jail.d/$selected_jail.conf"
              fi
              
if [ ! -z "$find_time" ]; then
                echo "findtime = $find_time" >> "/etc/fail2ban/jail.d/$selected_jail.conf"
              fi
              
              if [ ! -z "$max_retry" ]; then
                echo "maxretry = $max_retry" >> "/etc/fail2ban/jail.d/$selected_jail.conf"
              fi
              
              # Restart Fail2Ban to apply changes
              systemctl restart fail2ban
              
              log "Fail2Ban jail $selected_jail configured"
              dialog_info "Jail Configured" "The $selected_jail jail has been configured with the specified parameters."
              ;;
          esac
          ;;
        actions)
          # Configure actions
          local action_option=$(dialog_menu "Configure Actions" "Choose an option:" \
            "view" "View available actions" \
            "custom" "Create custom action" \
            "back" "Back to Fail2Ban menu")
          
          if [ -z "$action_option" ] || [ "$action_option" = "back" ]; then
            log "Action option selection cancelled"
            return
          fi
          
          case $action_option in
            view)
              # View available actions
              local available_actions=$(find /etc/fail2ban/action.d -name "*.conf" -exec basename {} .conf \; | sort)
              
              local action_info="Available Fail2Ban actions:\n\n"
              
              for action in $available_actions; do
                action_info+="$action\n"
              done
              
              dialog_info "Available Actions" "$action_info"
              ;;
            custom)
              # Create custom action
              local action_name=$(dialog_input "Action Name" "Enter a name for the custom action:" "custom-action")
              
              if [ -z "$action_name" ]; then
                log "Action name input cancelled"
                return
              fi
              
              local action_desc=$(dialog_input "Action Description" "Enter a description for the action:" "Custom action")
              
              if [ -z "$action_desc" ]; then
                action_desc="Custom action"
              fi
              
              local start_command=$(dialog_input "Start Command" "Enter the command to run when the action starts:" "")
              local ban_command=$(dialog_input "Ban Command" "Enter the command to run when banning an IP (<ip> will be replaced):" "iptables -I INPUT -s <ip> -j DROP")
              local unban_command=$(dialog_input "Unban Command" "Enter the command to run when unbanning an IP (<ip> will be replaced):" "iptables -D INPUT -s <ip> -j DROP")
              local stop_command=$(dialog_input "Stop Command" "Enter the command to run when the action stops:" "")
              
              # Create the action file
              cat > "/etc/fail2ban/action.d/$action_name.conf" << EOL
[Definition]
actionstart = $start_command
actionstop = $stop_command
actioncheck = 
actionban = $ban_command
actionunban = $unban_command

[Init]
name = $action_name
desc = $action_desc
EOL
              
              log "Custom Fail2Ban action $action_name created"
              dialog_info "Action Created" "The custom action '$action_name' has been created."
              ;;
          esac
          ;;
        ban)
          # Manually ban an IP address
          local ip_address=$(dialog_input "Ban IP" "Enter the IP address to ban:" "")
          
          if [ -z "$ip_address" ]; then
            log "IP address input cancelled"
            return
          fi
          
          # Validate IP address format
          if ! [[ "$ip_address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            dialog_info "Invalid IP" "The entered value is not a valid IPv4 address."
            log "Invalid IP address format: $ip_address"
            return
          fi
          
          # Get active jails
          local active_jails=$(fail2ban-client status | grep "Jail list" | sed 's/^.*: //' | tr ',' ' ')
          
          if [ -z "$active_jails" ]; then
            dialog_info "No Active Jails" "No active jails found. IP will not be banned."
            log "No active jails found"
            return
          fi
          
          local jail_options=()
          
          for jail in $active_jails; do
            jail_options+=("$jail" "Active jail")
          done
          
          local selected_jail=$(dialog_menu "Select Jail" "Select a jail to ban the IP in:" "${jail_options[@]}")
          
          if [ -z "$selected_jail" ]; then
            log "Jail selection cancelled"
            return
          fi
          
          # Ban the IP
          fail2ban-client set $selected_jail banip $ip_address
          
          log "IP address $ip_address manually banned in jail $selected_jail"
          dialog_info "IP Banned" "The IP address $ip_address has been banned in the $selected_jail jail."
          ;;
        unban)
          # Unban an IP address
          local active_jails=$(fail2ban-client status | grep "Jail list" | sed 's/^.*: //' | tr ',' ' ')
          
          if [ -z "$active_jails" ]; then
            dialog_info "No Active Jails" "No active jails found."
            log "No active jails found"
            return
          fi
          
          local jail_options=()
          
          for jail in $active_jails; do
            jail_options+=("$jail" "Active jail")
          done
          
          local selected_jail=$(dialog_menu "Select Jail" "Select a jail to view banned IPs:" "${jail_options[@]}")
          
          if [ -z "$selected_jail" ]; then
            log "Jail selection cancelled"
            return
          fi
          
          # Get banned IPs for the selected jail
          local banned_ips=$(fail2ban-client status $selected_jail | grep "IP list" | sed 's/^.*: //' | tr ',' ' ')
          
          if [ -z "$banned_ips" ]; then
            dialog_info "No Banned IPs" "No banned IPs found in the $selected_jail jail."
            log "No banned IPs found in jail $selected_jail"
            return
          fi
          
          local ip_options=()
          
          for ip in $banned_ips; do
            ip_options+=("$ip" "Banned IP")
          done
          
          local selected_ip=$(dialog_menu "Select IP" "Select an IP to unban:" "${ip_options[@]}")
          
          if [ -z "$selected_ip" ]; then
            log "IP selection cancelled"
            return
          fi
          
          # Unban the IP
          fail2ban-client set $selected_jail unbanip $selected_ip
          
          log "IP address $selected_ip unbanned from jail $selected_jail"
          dialog_info "IP Unbanned" "The IP address $selected_ip has been unbanned from the $selected_jail jail."
          ;;
        logs)
          # View Fail2Ban logs
          local log_file="/var/log/fail2ban.log"
          
          if [ ! -f "$log_file" ]; then
            dialog_info "Log Not Found" "Fail2Ban log file not found."
            log "Fail2Ban log file not found"
            return
          fi
          
          local log_lines=$(dialog_input "Log Lines" "Enter the number of log lines to view:" "100")
          
          if [ -z "$log_lines" ]; then
            log_lines="100"
          fi
          
          local logs=$(tail -n "$log_lines" "$log_file")
          dialog_info "Fail2Ban Logs" "Last $log_lines lines of Fail2Ban logs:\n\n$logs"
          ;;
      esac
      ;;
    rate)
      # Implement rate limiting
      # Check if required tools are installed
      if ! command -v iptables &> /dev/null; then
        if dialog_confirm "Install iptables" "iptables is not installed. Would you like to install it?"; then
          apt update
          apt install -y iptables
          track_installed_package "iptables"
          log "iptables installed"
        else
          dialog_info "iptables" "iptables is required for rate limiting."
          log "iptables installation cancelled"
          return
        fi
      fi
      
      # Rate limiting options
      local rate_option=$(dialog_menu "Rate Limiting" "Choose an option:" \
        "service" "Limit connections to a service" \
        "ip" "Limit connections from an IP" \
        "view" "View current rate limits" \
        "remove" "Remove rate limits" \
        "back" "Back to advanced firewall menu")
      
      if [ -z "$rate_option" ] || [ "$rate_option" = "back" ]; then
        log "Rate limiting option selection cancelled"
        return
      fi
      
      case $rate_option in
        service)
          # Limit connections to a service
          local service=$(dialog_menu "Select Service" "Choose a service to limit:" \
            "ssh" "SSH (port 22)" \
            "http" "HTTP (port 80)" \
            "https" "HTTPS (port 443)" \
            "ftp" "FTP (port 21)" \
            "smtp" "SMTP (port 25)" \
            "custom" "Custom port" \
            "back" "Back")
          
          if [ -z "$service" ] || [ "$service" = "back" ]; then
            log "Service selection cancelled"
            return
          fi
          
          local port=""
          case $service in
            ssh) port="22" ;;
            http) port="80" ;;
            https) port="443" ;;
            ftp) port="21" ;;
            smtp) port="25" ;;
            custom)
              port=$(dialog_input "Custom Port" "Enter the port number:" "")
              
              if [ -z "$port" ]; then
                log "Custom port input cancelled"
                return
              fi
              
              # Validate port number
              if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                dialog_info "Invalid Port" "The port number must be between 1 and 65535."
                log "Invalid port number: $port"
                return
              fi
              ;;
          esac
          
          local connections=$(dialog_input "Connections" "Enter the maximum number of connections per minute:" "10")
          
          if [ -z "$connections" ]; then
            log "Connections input cancelled"
            return
          fi
          
          # Validate connections number
          if ! [[ "$connections" =~ ^[0-9]+$ ]]; then
            dialog_info "Invalid Number" "Please enter a valid number."
            log "Invalid connections number: $connections"
            return
          fi
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/firewall"
          
          # Backup current iptables rules
          iptables-save > "$BACKUP_DIR/firewall/iptables_before_ratelimit_$(date +%Y%m%d%H%M%S).rules"
          
          # Check if rate limit chain exists
          iptables -L RATELIMIT >/dev/null 2>&1 || iptables -N RATELIMIT
          
          # Add rule to limit connections
          iptables -A RATELIMIT -p tcp --dport $port -m state --state NEW -m recent --set
          iptables -A RATELIMIT -p tcp --dport $port -m state --state NEW -m recent --update --seconds 60 --hitcount $connections -j DROP
          
          # Make sure the chain is used
          iptables -C INPUT -j RATELIMIT >/dev/null 2>&1 || iptables -A INPUT -j RATELIMIT
          
          log "Rate limiting for port $port set to $connections connections per minute"
          dialog_info "Rate Limit Set" "Rate limiting for port $port has been set to $connections connections per minute."
          ;;
        ip)
          # Limit connections from an IP
          local ip_address=$(dialog_input "IP Address" "Enter the IP address to limit (use 0.0.0.0/0 for all IPs):" "0.0.0.0/0")
          
          if [ -z "$ip_address" ]; then
            log "IP address input cancelled"
            return
          fi
          
          local connections=$(dialog_input "Connections" "Enter the maximum number of connections per minute:" "30")
          
          if [ -z "$connections" ]; then
            log "Connections input cancelled"
            return
          fi
          
          # Validate connections number
          if ! [[ "$connections" =~ ^[0-9]+$ ]]; then
            dialog_info "Invalid Number" "Please enter a valid number."
            log "Invalid connections number: $connections"
            return
          fi
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/firewall"
          
          # Backup current iptables rules
          iptables-save > "$BACKUP_DIR/firewall/iptables_before_ratelimit_$(date +%Y%m%d%H%M%S).rules"
          
          # Check if rate limit chain exists
          iptables -L RATELIMIT >/dev/null 2>&1 || iptables -N RATELIMIT
          
          # Add rule to limit connections
          iptables -A RATELIMIT -s $ip_address -m state --state NEW -m recent --set
          iptables -A RATELIMIT -s $ip_address -m state --state NEW -m recent --update --seconds 60 --hitcount $connections -j DROP
          
          # Make sure the chain is used
          iptables -C INPUT -j RATELIMIT >/dev/null 2>&1 || iptables -A INPUT -j RATELIMIT
          
          log "Rate limiting for IP $ip_address set to $connections connections per minute"
          dialog_info "Rate Limit Set" "Rate limiting for IP $ip_address has been set to $connections connections per minute."
          ;;
        view)
          # View current rate limits
          local rate_limits=$(iptables -L RATELIMIT -v 2>/dev/null || echo "No rate limits found")
          dialog_info "Current Rate Limits" "$rate_limits"
          ;;
        remove)
          # Remove rate limits
          if dialog_confirm "Remove Rate Limits" "Are you sure you want to remove all rate limits?"; then
            # Create backup directory
            mkdir -p "$BACKUP_DIR/firewall"
            
            # Backup current iptables rules
            iptables-save > "$BACKUP_DIR/firewall/iptables_before_ratelimit_remove_$(date +%Y%m%d%H%M%S).rules"
            
            # Check if rate limit chain exists
            if iptables -L RATELIMIT >/dev/null 2>&1; then
              # Remove references to the chain
              iptables -D INPUT -j RATELIMIT 2>/dev/null || true
              
              # Flush and delete the chain
              iptables -F RATELIMIT
              iptables -X RATELIMIT
            fi
            
            log "Rate limits removed"
            dialog_info "Rate Limits Removed" "All rate limits have been removed."
          else
            log "Rate limit removal cancelled"
          fi
          ;;
      esac
      ;;
    logs)
      # View and analyze firewall logs
      local log_option=$(dialog_menu "Firewall Logs" "Choose an option:" \
        "ufw" "View UFW logs" \
        "iptables" "View iptables log entries" \
        "analyze" "Analyze firewall logs" \
        "back" "Back to advanced firewall menu")
      
      if [ -z "$log_option" ] || [ "$log_option" = "back" ]; then
        log "Log option selection cancelled"
        return
      fi
      
      case $log_option in
        ufw)
          # View UFW logs
          local log_file="/var/log/ufw.log"
          
          if [ ! -f "$log_file" ]; then
            # Check alternative log file
            log_file="/var/log/kern.log"
            if [ ! -f "$log_file" ]; then
              dialog_info "Log Not Found" "UFW log files not found."
              log "UFW log files not found"
              return
            fi
          fi
          
          local log_lines=$(dialog_input "Log Lines" "Enter the number of UFW log lines to view:" "50")
          
          if [ -z "$log_lines" ]; then
            log_lines="50"
          fi
          
          local ufw_logs=$(grep "UFW" "$log_file" | tail -n "$log_lines")
          dialog_info "UFW Logs" "Last $log_lines lines of UFW logs:\n\n$ufw_logs"
          ;;
        iptables)
          # View iptables log entries
          local log_file="/var/log/kern.log"
          
          if [ ! -f "$log_file" ]; then
            dialog_info "Log Not Found" "iptables log file not found."
            log "iptables log file not found"
            return
          fi
          
          local log_lines=$(dialog_input "Log Lines" "Enter the number of iptables log lines to view:" "50")
          
          if [ -z "$log_lines" ]; then
            log_lines="50"
          fi
          
          local iptables_logs=$(grep "IN=" "$log_file" | grep "OUT=" | tail -n "$log_lines")
          dialog_info "iptables Logs" "Last $log_lines lines of iptables logs:\n\n$iptables_logs"
          ;;
        analyze)
          # Analyze firewall logs
          local log_file="/var/log/kern.log"
          
          if [ ! -f "$log_file" ]; then
            dialog_info "Log Not Found" "Firewall log file not found."
            log "Firewall log file not found"
            return
          fi
          
          # Create a temporary file for analysis
          local temp_file=$(mktemp)
          
          # Extract important parts from log
          grep "IN=" "$log_file" | grep "OUT=" > "$temp_file"
          
          # Analyze the logs
          local analysis=""
          
          # Top source IPs
          analysis+="TOP SOURCE IPS:\n"
          analysis+=$(grep -o "SRC=[^ ]*" "$temp_file" | sort | uniq -c | sort -nr | head -10 | sed 's/SRC=//')
          analysis+="\n\n"
          
          # Top destination IPs
          analysis+="TOP DESTINATION IPS:\n"
          analysis+=$(grep -o "DST=[^ ]*" "$temp_file" | sort | uniq -c | sort -nr | head -10 | sed 's/DST=//')
          analysis+="\n\n"
          
          # Top protocols
          analysis+="TOP PROTOCOLS:\n"
          analysis+=$(grep -o "PROTO=[^ ]*" "$temp_file" | sort | uniq -c | sort -nr | head -5 | sed 's/PROTO=//')
          analysis+="\n\n"
          
          # Top ports
          analysis+="TOP DESTINATION PORTS:\n"
          analysis+=$(grep -o "DPT=[^ ]*" "$temp_file" | sort | uniq -c | sort -nr | head -10 | sed 's/DPT=//')
          analysis+="\n\n"
          
          # Clean up
          rm -f "$temp_file"
          
          dialog_info "Firewall Log Analysis" "$analysis"
          ;;
      esac
      ;;
    script)
      # Create custom firewall script
      local script_option=$(dialog_menu "Custom Firewall Script" "Choose an option:" \
        "create" "Create a new firewall script" \
        "edit" "Edit existing firewall script" \
        "run" "Run firewall script" \
        "schedule" "Schedule firewall script" \
        "back" "Back to advanced firewall menu")
      
      if [ -z "$script_option" ] || [ "$script_option" = "back" ]; then
        log "Script option selection cancelled"
        return
      fi
      
      local script_dir="/etc/firewall"
      mkdir -p "$script_dir"
      
      case $script_option in
        create)
          # Create a new firewall script
          local script_name=$(dialog_input "Script Name" "Enter a name for the firewall script (without .sh extension):" "firewall-custom")
          
          if [ -z "$script_name" ]; then
            log "Script name input cancelled"
            return
          fi
          
          local script_file="$script_dir/$script_name.sh"
          
          # Check if script already exists
          if [ -f "$script_file" ]; then
            if ! dialog_confirm "Overwrite Script" "A script with this name already exists. Do you want to overwrite it?"; then
              log "Script overwrite cancelled"
              return
            fi
          fi
          
          # Create a template script
          cat > "$script_file" << 'EOL'
#!/bin/bash

# Custom firewall script
# Created by Ubuntu Setup Script

# Log file
LOG_FILE="/var/log/firewall-custom.log"

# Log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting custom firewall script"

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (port 22)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP and HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "FIREWALL:DROP: " --log-level 4

log "Firewall rules applied successfully"
EOL
          
          # Make script executable
          chmod +x "$script_file"
          
          log "Custom firewall script created: $script_file"
          dialog_info "Script Created" "The custom firewall script has been created at $script_file.\n\nYou can edit it to add your own rules."
          ;;
        edit)
          # Edit existing firewall script
          local available_scripts=$(find "$script_dir" -name "*.sh" -type f)
          
          if [ -z "$available_scripts" ]; then
            dialog_info "No Scripts" "No firewall scripts found."
            log "No firewall scripts found"
            return
          fi
          
          local script_options=()
          local counter=0
          
          while read -r script_file; do
            script_options+=("$script_file" "Firewall script")
            counter=$((counter + 1))
          done <<< "$available_scripts"
          
          local selected_script=$(dialog_menu "Edit Script" "Select a script to edit:" "${script_options[@]}")
          
          if [ -z "$selected_script" ]; then
            log "Script selection cancelled"
            return
          fi
          
          # Check if nano is installed
          if [ -z "$(which nano 2>/dev/null)" ]; then
            apt update && apt install -y nano
            track_installed_package "nano"
          fi
          
          # Show information message
          dialog_info "Edit Script" "The text editor will now open to edit the firewall script.\n\nPress Ctrl+X to save and exit when you're done."
          
          # Open editor
          nano "$selected_script"
          
          log "Firewall script edited: $selected_script"
          dialog_info "Script Edited" "The firewall script has been edited."
          ;;
        run)
          # Run firewall script
          local available_scripts=$(find "$script_dir" -name "*.sh" -type f)
          
          if [ -z "$available_scripts" ]; then
            dialog_info "No Scripts" "No firewall scripts found."
            log "No firewall scripts found"
            return
          fi
          
          local script_options=()
          local counter=0
          
          while read -r script_file; do
            script_options+=("$script_file" "Firewall script")
            counter=$((counter + 1))
          done <<< "$available_scripts"
          
          local selected_script=$(dialog_menu "Run Script" "Select a script to run:" "${script_options[@]}")
          
          if [ -z "$selected_script" ]; then
            log "Script selection cancelled"
            return
          fi
          
          # Ask for confirmation
          if ! dialog_confirm "Run Script" "Are you sure you want to run the selected firewall script?\n\nThis may change your firewall rules and could affect your connectivity."; then
            log "Script execution cancelled"
            return
          fi
          
          # Create backup directory
          mkdir -p "$BACKUP_DIR/firewall"
          
          # Backup current iptables rules
          iptables-save > "$BACKUP_DIR/firewall/iptables_before_script_$(date +%Y%m%d%H%M%S).rules"
          
          # Run the script
          bash "$selected_script"
          
          log "Firewall script executed: $selected_script"
          dialog_info "Script Executed" "The firewall script has been executed."
          ;;
        schedule)
          # Schedule firewall script
          local available_scripts=$(find "$script_dir" -name "*.sh" -type f)
          
          if [ -z "$available_scripts" ]; then
            dialog_info "No Scripts" "No firewall scripts found."
            log "No firewall scripts found"
            return
          fi
          
          local script_options=()
          local counter=0
          
          while read -r script_file; do
            script_options+=("$script_file" "Firewall script")
            counter=$((counter + 1))
          done <<< "$available_scripts"
          
          local selected_script=$(dialog_menu "Schedule Script" "Select a script to schedule:" "${script_options[@]}")
          
          if [ -z "$selected_script" ]; then
            log "Script selection cancelled"
            return
          fi
          
          local schedule_type=$(dialog_menu "Schedule Type" "Choose when to run the script:" \
            "boot" "Run at system boot" \
            "daily" "Run daily" \
            "weekly" "Run weekly" \
            "monthly" "Run monthly" \
            "custom" "Custom cron schedule" \
            "back" "Back")
          
          if [ -z "$schedule_type" ] || [ "$schedule_type" = "back" ]; then
            log "Schedule type selection cancelled"
            return
          fi
          
          local cron_entry=""
          case $schedule_type in
            boot)
              cron_entry="@reboot root $selected_script"
              ;;
            daily)
              local time=$(dialog_input "Daily Time" "Enter the time to run the script daily (HH:MM):" "03:00")
              
              if [ -z "$time" ]; then
                log "Time input cancelled"
                return
              fi
              
              local hour=$(echo "$time" | cut -d':' -f1)
              local minute=$(echo "$time" | cut -d':' -f2)
              
              cron_entry="$minute $hour * * * root $selected_script"
              ;;
            weekly)
              local day=$(dialog_menu "Day of Week" "Choose the day of the week:" \
                "1" "Monday" \
                "2" "Tuesday" \
                "3" "Wednesday" \
                "4" "Thursday" \
                "5" "Friday" \
                "6" "Saturday" \
                "0" "Sunday")
              
              if [ -z "$day" ]; then
                log "Day selection cancelled"
                return
              fi
              
              local time=$(dialog_input "Weekly Time" "Enter the time to run the script weekly (HH:MM):" "03:00")
              
              if [ -z "$time" ]; then
                log "Time input cancelled"
                return
              fi
              
              local hour=$(echo "$time" | cut -d':' -f1)
              local minute=$(echo "$time" | cut -d':' -f2)
              
              cron_entry="$minute $hour * * $day root $selected_script"
              ;;
            monthly)
              local day_of_month=$(dialog_input "Day of Month" "Enter the day of the month to run the script (1-31):" "1")
              
              if [ -z "$day_of_month" ]; then
                log "Day of month input cancelled"
                return
              fi
              
              local time=$(dialog_input "Monthly Time" "Enter the time to run the script monthly (HH:MM):" "03:00")
              
              if [ -z "$time" ]; then
                log "Time input cancelled"
                return
              fi
              
              local hour=$(echo "$time" | cut -d':' -f1)
              local minute=$(echo "$time" | cut -d':' -f2)
              
              cron_entry="$minute $hour $day_of_month * * root $selected_script"
              ;;
            custom)
              local custom_schedule=$(dialog_input "Custom Schedule" "Enter the custom cron schedule (minute hour day month weekday):" "0 3 * * *")
              
              if [ -z "$custom_schedule" ]; then
                log "Custom schedule input cancelled"
                return
              fi
              
              cron_entry="$custom_schedule root $selected_script"
              ;;
          esac
          
          # Create cron file
          local script_name=$(basename "$selected_script" .sh)
          local cron_file="/etc/cron.d/firewall-$script_name"
          
          echo "# Firewall script schedule created by Ubuntu Setup Script" > "$cron_file"
          echo "SHELL=/bin/bash" >> "$cron_file"
          echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" >> "$cron_file"
          echo "" >> "$cron_file"
          echo "$cron_entry" >> "$cron_file"
          
          chmod 644 "$cron_file"
          
          log "Firewall script scheduled: $selected_script"
          dialog_info "Script Scheduled" "The firewall script has been scheduled as requested."
          ;;
      esac
      ;;
  esac
}

# Function for firewall management main menu
firewall_management() {
  log "Firewall management started"
  
  # Check if UFW or iptables is installed
  local has_ufw=0
  local has_iptables=0
  
  if command -v ufw &> /dev/null; then
    has_ufw=1
  fi
  
  if command -v iptables &> /dev/null; then
    has_iptables=1
  fi
  
  while true; do
    local action=$(dialog_menu "Firewall Management" "Choose an option:" \
      "ufw" "Manage UFW (Uncomplicated Firewall)" \
      "advanced" "Advanced firewall configuration" \
      "ports" "Open/close specific ports" \
      "services" "Allow/block specific services" \
      "status" "View firewall status" \
      "log" "View firewall logs" \
      "backup" "Backup/restore firewall rules" \
      "install" "Install firewall software" \
      "back" "Back to main menu")
    
    case $action in
      ufw)
        if [ $has_ufw -eq 1 ]; then
          manage_ufw
        else
          if dialog_confirm "Install UFW" "UFW is not installed. Do you want to install it now?"; then
            apt update
            apt install -y ufw
            track_installed_package "ufw"
            has_ufw=1
            log "UFW installed"
            manage_ufw
          else
            log "UFW installation cancelled"
          fi
        fi
        ;;
      advanced)
        configure_advanced_firewall
        ;;
      ports)
        manage_ports
        ;;
      services)
        manage_services
        ;;
      status)
        view_firewall_status
        ;;
      log)
        view_firewall_logs
        ;;
      backup)
        backup_firewall
        ;;
      install)
        install_firewall
        ;;
      back|"")
        log "Firewall management exited"
        return
        ;;
    esac
  done
}

# Function for managing specific ports
manage_ports() {
  log "Port management started"
  
  local port_action=$(dialog_menu "Port Management" "Choose an action:" \
    "open" "Open a port" \
    "close" "Close a port" \
    "check" "Check if a port is open" \
    "list" "List open ports" \
    "back" "Back to firewall menu")
  
  if [ -z "$port_action" ] || [ "$port_action" = "back" ]; then
    log "Port action selection cancelled"
    return
  fi
  
  case $port_action in
    open)
      # Open a port
      local port=$(dialog_input "Open Port" "Enter the port number to open:" "")
      
      if [ -z "$port" ]; then
        log "Port number input cancelled"
        return
      fi
      
      # Validate port number
      if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        dialog_info "Invalid Port" "The port number must be between 1 and 65535."
        log "Invalid port number: $port"
        return
      fi
      
      local protocol=$(dialog_menu "Protocol" "Select the protocol:" \
        "tcp" "TCP" \
        "udp" "UDP" \
        "both" "Both TCP and UDP" \
        "back" "Cancel")
      
      if [ -z "$protocol" ] || [ "$protocol" = "back" ]; then
        log "Protocol selection cancelled"
        return
      fi
      
      # Use appropriate firewall command
      if command -v ufw &> /dev/null; then
        if [ "$protocol" = "tcp" ]; then
          ufw allow $port/tcp
        elif [ "$protocol" = "udp" ]; then
          ufw allow $port/udp
        else
          ufw allow $port/tcp
          ufw allow $port/udp
        fi
      elif command -v iptables &> /dev/null; then
        if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
          iptables -A INPUT -p tcp --dport $port -j ACCEPT
        fi
        if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
          iptables -A INPUT -p udp --dport $port -j ACCEPT
        fi
      else
        dialog_info "No Firewall" "No supported firewall found. Please install UFW or iptables."
        log "No supported firewall found"
        return
      fi
      
      log "Port $port opened for $protocol"
      dialog_info "Port Opened" "Port $port has been opened for $protocol."
      ;;
    close)
      # Close a port
      local port=$(dialog_input "Close Port" "Enter the port number to close:" "")
      
      if [ -z "$port" ]; then
        log "Port number input cancelled"
        return
      fi
      
      # Validate port number
      if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        dialog_info "Invalid Port" "The port number must be between 1 and 65535."
        log "Invalid port number: $port"
        return
      fi
      
      local protocol=$(dialog_menu "Protocol" "Select the protocol:" \
        "tcp" "TCP" \
        "udp" "UDP" \
        "both" "Both TCP and UDP" \
        "back" "Cancel")
      
      if [ -z "$protocol" ] || [ "$protocol" = "back" ]; then
        log "Protocol selection cancelled"
        return
      fi
      
      # Use appropriate firewall command
      if command -v ufw &> /dev/null; then
        if [ "$protocol" = "tcp" ]; then
          ufw deny $port/tcp
        elif [ "$protocol" = "udp" ]; then
          ufw deny $port/udp
        else
          ufw deny $port/tcp
          ufw deny $port/udp
        fi
      elif command -v iptables &> /dev/null; then
        if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
          iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
          iptables -A INPUT -p tcp --dport $port -j DROP
        fi
        if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
          iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
          iptables -A INPUT -p udp --dport $port -j DROP
        fi
      else
        dialog_info "No Firewall" "No supported firewall found. Please install UFW or iptables."
        log "No supported firewall found"
        return
      fi
      
      log "Port $port closed for $protocol"
      dialog_info "Port Closed" "Port $port has been closed for $protocol."
      ;;
    check)
      # Check if a port is open
      local port=$(dialog_input "Check Port" "Enter the port number to check:" "")
      
      if [ -z "$port" ]; then
        log "Port number input cancelled"
        return
      fi
      
      # Validate port number
      if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        dialog_info "Invalid Port" "The port number must be between 1 and 65535."
        log "Invalid port number: $port"
        return
      fi
      
      local result=""
      
      # Check if port is open using ss
      if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
          result+="Port $port is OPEN (listening) on this system.\n\n"
          result+="Listening programs:\n"
          result+=$(ss -tulnp | grep ":$port " | awk '{print $7}' | sed 's/users:(("\(.*\)",.*)/\1/')
          result+="\n\n"
        else
          result+="Port $port is not listening on this system.\n\n"
        fi
      else
        result+="Unable to check listening ports (ss command not found).\n\n"
      fi
      
      # Check firewall rules for the port
      if command -v ufw &> /dev/null; then
        result+="UFW Rules for port $port:\n"
        result+=$(ufw status | grep $port)
        result+="\n\n"
      fi
      
      if command -v iptables &> /dev/null; then
        result+="iptables Rules for port $port:\n"
        result+=$(iptables -L -n | grep ":$port")
        result+="\n"
      fi
      
      dialog_info "Port Status" "$result"
      ;;
    list)
      # List open ports
      local open_ports=""
      
      # Get list of listening ports
      if command -v ss &> /dev/null; then
        open_ports+="LISTENING PORTS:\n"
        open_ports+=$(ss -tuln | grep -v "^Netid" | awk '{print $5}' | grep -o '[0-9]*$' | sort -n | uniq | 
          while read port; do 
            printf "%-5s %s\n" "$port" "$(ss -tulnp | grep ":$port " | awk '{print $7}' | sed 's/users:(("\(.*\)",.*)/\1/' | head -1)"; 
          done)
        open_ports+="\n\n"
      else
        open_ports+="Unable to list listening ports (ss command not found).\n\n"
      fi
      
      # Get firewall rules
      if command -v ufw &> /dev/null; then
        open_ports+="UFW ALLOWED PORTS:\n"
        open_ports+=$(ufw status | grep -i allow)
        open_ports+="\n\n"
      fi
      
      if command -v iptables &> /dev/null; then
        open_ports+="IPTABLES ALLOWED PORTS:\n"
        open_ports+=$(iptables -L -n | grep "dpt:" | grep "ACCEPT" | awk '{print $7}' | sed 's/dpt://' | sort -n | uniq | 
          while read port; do 
            echo "Port: $port"; 
          done)
        open_ports+="\n"
      fi
      
      dialog_info "Open Ports" "$open_ports"
      ;;
  esac
}

# Function for managing specific services
manage_services() {
  log "Service management started"
  
  local service_action=$(dialog_menu "Service Management" "Choose an action:" \
    "allow" "Allow a service" \
    "block" "Block a service" \
    "status" "Check service firewall status" \
    "list" "List available services" \
    "back" "Back to firewall menu")
  
  if [ -z "$service_action" ] || [ "$service_action" = "back" ]; then
    log "Service action selection cancelled"
    return
  fi
  
  case $service_action in
    allow|block)
      # Get list of available services
      local available_services=""
      
      if command -v ufw &> /dev/null; then
        available_services=$(ufw app list | tail -n +2 | awk '{print $1}')
      fi
      
      # Add common services if not already in the list
      local common_services="SSH HTTP HTTPS FTP SMTP DNS"
      for service in $common_services; do
        if ! grep -q "$service" <<< "$available_services"; then
          available_services+=" $service"
        fi
      done
      
      # Build menu options
      local service_options=()
      for service in $available_services; do
        service_options+=("$service" "Network service")
      done
      
      service_options+=("custom" "Custom service/port")
      
      # Let user choose a service
      local selected_service=$(dialog_menu "Select Service" "Choose a service:" "${service_options[@]}")
      
      if [ -z "$selected_service" ]; then
        log "Service selection cancelled"
        return
      fi
      
      local service_port=""
      if [ "$selected_service" = "custom" ]; then
        service_port=$(dialog_input "Custom Service" "Enter the port number for the custom service:" "")
        
        if [ -z "$service_port" ]; then
          log "Custom service input cancelled"
          return
        fi
        
        # Validate port number
        if ! [[ "$service_port" =~ ^[0-9]+$ ]] || [ "$service_port" -lt 1 ] || [ "$service_port" -gt 65535 ]; then
          dialog_info "Invalid Port" "The port number must be between 1 and 65535."
          log "Invalid port number: $service_port"
          return
        fi
        
        selected_service="port $service_port"
      else
        # Map service name to port if needed
        case $selected_service in
          SSH) service_port="22" ;;
          HTTP) service_port="80" ;;
          HTTPS) service_port="443" ;;
          FTP) service_port="21" ;;
          SMTP) service_port="25" ;;
          DNS) service_port="53" ;;
        esac
      fi
      
      # Allow or block the service
      if command -v ufw &> /dev/null; then
        if [ "$service_action" = "allow" ]; then
          if [ -z "$service_port" ]; then
            ufw allow "$selected_service"
          else
            ufw allow "$service_port/tcp"
            
            # Also allow UDP for DNS
            if [ "$selected_service" = "DNS" ]; then
              ufw allow "$service_port/udp"
            fi
          fi
        else
          if [ -z "$service_port" ]; then
            ufw deny "$selected_service"
          else
            ufw deny "$service_port/tcp"
            
            # Also deny UDP for DNS
            if [ "$selected_service" = "DNS" ]; then
              ufw deny "$service_port/udp"
            fi
          fi
        fi
      elif command -v iptables &> /dev/null; then
        if [ ! -z "$service_port" ]; then
          if [ "$service_action" = "allow" ]; then
            iptables -A INPUT -p tcp --dport "$service_port" -j ACCEPT
            
            # Also allow UDP for DNS
            if [ "$selected_service" = "DNS" ]; then
              iptables -A INPUT -p udp --dport "$service_port" -j ACCEPT
            fi
          else
            iptables -D INPUT -p tcp --dport "$service_port" -j ACCEPT 2>/dev/null
            iptables -A INPUT -p tcp --dport "$service_port" -j DROP
            
            # Also deny UDP for DNS
            if [ "$selected_service" = "DNS" ]; then
              iptables -D INPUT -p udp --dport "$service_port" -j ACCEPT 2>/dev/null
              iptables -A INPUT -p udp --dport "$service_port" -j DROP
            fi
          fi
        else
          dialog_info "No Port Mapping" "No port mapping available for this service."
          log "No port mapping for service: $selected_service"
          return
        fi
      else
        dialog_info "No Firewall" "No supported firewall found. Please install UFW or iptables."
        log "No supported firewall found"
        return
      fi
      
      log "Service $selected_service ${service_action}ed"
      dialog_info "Service ${service_action^}ed" "Service $selected_service has been ${service_action}ed."
      ;;
    status)
      # Check service firewall status
      # Get list of available services
      local available_services=""
      
      if command -v ufw &> /dev/null; then
        available_services=$(ufw app list | tail -n +2 | awk '{print $1}')
      fi
      
      # Add common services if not already in the list
      local common_services="SSH HTTP HTTPS FTP SMTP DNS"
      for service in $common_services; do
        if ! grep -q "$service" <<< "$available_services"; then
          available_services+=" $service"
        fi
      done
      
      # Build menu options
      local service_options=()
      for service in $available_services; do
        service_options+=("$service" "Network service")
      done
      
      service_options+=("custom" "Custom service/port")
      
      # Let user choose a service
      local selected_service=$(dialog_menu "Select Service" "Choose a service to check:" "${service_options[@]}")
      
      if [ -z "$selected_service" ]; then
        log "Service selection cancelled"
        return
      fi
      
      local service_port=""
      if [ "$selected_service" = "custom" ]; then
        service_port=$(dialog_input "Custom Service" "Enter the port number for the custom service:" "")
        
        if [ -z "$service_port" ]; then
          log "Custom service input cancelled"
          return
        fi
        
        # Validate port number
        if ! [[ "$service_port" =~ ^[0-9]+$ ]] || [ "$service_port" -lt 1 ] || [ "$service_port" -gt 65535 ]; then
          dialog_info "Invalid Port" "The port number must be between 1 and 65535."
          log "Invalid port number: $service_port"
          return
        fi
        
        selected_service="port $service_port"
      else
        # Map service name to port if needed
        case $selected_service in
          SSH) service_port="22" ;;
          HTTP) service_port="80" ;;
          HTTPS) service_port="443" ;;
          FTP) service_port="21" ;;
          SMTP) service_port="25" ;;
          DNS) service_port="53" ;;
        esac
      fi
      
      local status_output=""
      
      # Check firewall rules for the service
      if command -v ufw &> /dev/null; then
        status_output+="UFW Rules for $selected_service:\n"
        if [ -z "$service_port" ]; then
          status_output+=$(ufw status | grep "$selected_service")
        else
          status_output+=$(ufw status | grep "$service_port/")
        fi
        status_output+="\n\n"
      fi
      
      if command -v iptables &> /dev/null && [ ! -z "$service_port" ]; then
        status_output+="iptables Rules for $selected_service (port $service_port):\n"
        status_output+=$(iptables -L -n | grep "dpt:$service_port")
        status_output+="\n\n"
      fi
      
      # Check if service is running
      if command -v ss &> /dev/null && [ ! -z "$service_port" ]; then
        status_output+="Service status (port $service_port):\n"
        if ss -tuln | grep -q ":$service_port "; then
          status_output+="Service is RUNNING on port $service_port\n"
          status_output+="Listening program: $(ss -tulnp | grep ":$service_port " | awk '{print $7}' | sed 's/users:(("\(.*\)",.*)/\1/')"
        else
          status_output+="No service is listening on port $service_port"
        fi
      fi
      
      dialog_info "Service Status" "$status_output"
      ;;
    list)
      # List available services
      local services_output=""
      
      # Get list of available UFW services
      if command -v ufw &> /dev/null; then
        services_output+="AVAILABLE UFW APPLICATION PROFILES:\n"
        services_output+=$(ufw app list)
        services_output+="\n\n"
      fi
      
      # List common services and ports
      services_output+="COMMON SERVICES AND PORTS:\n"
      services_output+="SSH - Port 22/tcp\n"
      services_output+="HTTP - Port 80/tcp\n"
      services_output+="HTTPS - Port 443/tcp\n"
      services_output+="FTP - Port 21/tcp\n"
      services_output+="SMTP - Port 25/tcp\n"
      services_output+="POP3 - Port 110/tcp\n"
      services_output+="IMAP - Port 143/tcp\n"
      services_output+="DNS - Port 53/tcp,udp\n"
      services_output+="MySQL/MariaDB - Port 3306/tcp\n"
      services_output+="PostgreSQL - Port 5432/tcp\n"
      services_output+="MongoDB - Port 27017/tcp\n"
      services_output+="Redis - Port 6379/tcp\n"
      
      dialog_info "Available Services" "$services_output"
      ;;
  esac
}

# Function for viewing firewall status
view_firewall_status() {
  log "Viewing firewall status"
  
  local status_output=""
  
  # Check UFW status
  if command -v ufw &> /dev/null; then
    status_output+="UFW STATUS:\n"
    status_output+=$(ufw status verbose)
    status_output+="\n\n"
  fi
  
  # Check iptables status
  if command -v iptables &> /dev/null; then
    status_output+="IPTABLES STATUS:\n"
    status_output+=$(iptables -L -v --line-numbers)
    status_output+="\n\n"
  fi
  
  # If no firewall is installed
  if [ -z "$status_output" ]; then
    status_output="No supported firewall (UFW or iptables) is installed on this system."
  fi
  
  dialog_info "Firewall Status" "$status_output"
}

# Function for viewing firewall logs
view_firewall_logs() {
  log "Viewing firewall logs"
  
  local log_option=$(dialog_menu "Firewall Logs" "Choose a log to view:" \
    "ufw" "UFW logs" \
    "kern" "Kernel/iptables logs" \
    "fail2ban" "Fail2Ban logs" \
    "back" "Back to firewall menu")
  
  if [ -z "$log_option" ] || [ "$log_option" = "back" ]; then
    log "Log option selection cancelled"
    return
  fi
  
  local log_file=""
  local log_command=""
  
  case $log_option in
    ufw)
      # UFW logs
      if [ -f "/var/log/ufw.log" ]; then
        log_file="/var/log/ufw.log"
      elif [ -f "/var/log/kern.log" ]; then
        log_file="/var/log/kern.log"
        log_command="grep UFW"
      else
        dialog_info "Log Not Found" "UFW log file not found."
        log "UFW log file not found"
        return
      fi
      ;;
    kern)
      # Kernel/iptables logs
      if [ -f "/var/log/kern.log" ]; then
        log_file="/var/log/kern.log"
        log_command="grep -E 'IN=|OUT='"
      else
        dialog_info "Log Not Found" "Kernel log file not found."
        log "Kernel log file not found"
        return
      fi
      ;;
    fail2ban)
      # Fail2Ban logs
      if [ -f "/var/log/fail2ban.log" ]; then
        log_file="/var/log/fail2ban.log"
      else
        dialog_info "Log Not Found" "Fail2Ban log file not found."
        log "Fail2Ban log file not found"
        return
      fi
      ;;
  esac
  
  local log_lines=$(dialog_input "Log Lines" "Enter the number of log lines to view:" "100")
  
  if [ -z "$log_lines" ]; then
    log_lines="100"
  fi
  
  local logs=""
  if [ -z "$log_command" ]; then
    logs=$(tail -n "$log_lines" "$log_file")
  else
    logs=$(eval "$log_command $log_file | tail -n $log_lines")
  fi
  
  dialog_info "Firewall Logs" "Last $log_lines lines of $log_option logs:\n\n$logs"
}

# Function for backing up and restoring firewall rules
backup_firewall() {
  log "Firewall backup/restore started"
  
  local backup_option=$(dialog_menu "Backup/Restore" "Choose an option:" \
    "backup" "Backup current firewall rules" \
    "restore" "Restore firewall rules from backup" \
    "back" "Back to firewall menu")
  
  if [ -z "$backup_option" ] || [ "$backup_option" = "back" ]; then
    log "Backup option selection cancelled"
    return
  fi
  
  case $backup_option in
    backup)
      # Backup current firewall rules
      local backup_dir="$BACKUP_DIR/firewall"
      mkdir -p "$backup_dir"
      
      local timestamp=$(date +%Y%m%d%H%M%S)
      local ufw_backup="$backup_dir/ufw_backup_$timestamp.rules"
      local iptables_backup="$backup_dir/iptables_backup_$timestamp.rules"
      
      # Backup UFW rules
      if command -v ufw &> /dev/null; then
        ufw status verbose > "$ufw_backup"
        cp /etc/ufw/user.rules "$ufw_backup.conf" 2>/dev/null
      fi
      
      # Backup iptables rules
      if command -v iptables &> /dev/null; then
        iptables-save > "$iptables_backup"
      fi
      
      log "Firewall rules backed up to $backup_dir"
      dialog_info "Backup Created" "The firewall rules have been backed up to:\n\n$backup_dir"
      ;;
    restore)
      # Restore firewall rules from backup
      local backup_dir="$BACKUP_DIR/firewall"
      
      if [ ! -d "$backup_dir" ]; then
        dialog_info "No Backups" "No backup directory found."
        log "No firewall backup directory found"
        return
      fi
      
      # Find backup files
      local ufw_backups=$(find "$backup_dir" -name "ufw_backup_*.rules.conf" -type f 2>/dev/null)
      local iptables_backups=$(find "$backup_dir" -name "iptables_backup_*.rules" -type f 2>/dev/null)
      
      if [ -z "$ufw_backups" ] && [ -z "$iptables_backups" ]; then
        dialog_info "No Backups" "No firewall backup files found."
        log "No firewall backup files found"
        return
      fi
      
      local firewall_type=$(dialog_menu "Restore Type" "Choose which firewall type to restore:" \
        "ufw" "Restore UFW rules" \
        "iptables" "Restore iptables rules" \
        "back" "Cancel")
      
      if [ -z "$firewall_type" ] || [ "$firewall_type" = "back" ]; then
        log "Firewall type selection cancelled"
        return
      fi
      
      case $firewall_type in
        ufw)
          if [ -z "$ufw_backups" ]; then
            dialog_info "No UFW Backups" "No UFW backup files found."
            log "No UFW backup files found"
            return
          fi
          
          # Build menu options
          local backup_options=()
          local counter=0
          
          while read -r backup_file; do
            local backup_date=$(basename "$backup_file" | sed 's/ufw_backup_\(.*\)\.rules\.conf/\1/')
            backup_date=$(date -d "${backup_date:0:8} ${backup_date:8:2}:${backup_date:10:2}:${backup_date:12:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$backup_date")
            backup_options+=("$backup_file" "Backup from $backup_date")
            counter=$((counter + 1))
          done <<< "$ufw_backups"
          
          # Let user choose a backup file
          local selected_backup=$(dialog_menu "Select Backup" "Choose a UFW backup to restore:" "${backup_options[@]}")
          
          if [ -z "$selected_backup" ]; then
            log "Backup selection cancelled"
            return
          fi
          
          # Ask for confirmation
          if ! dialog_confirm "Restore Backup" "Are you sure you want to restore the UFW configuration from this backup?\n\nThis will overwrite your current firewall rules."; then
            log "Backup restoration cancelled"
            return
          fi
          
          # Disable UFW first
          ufw --force disable
          
          # Restore the rules
          cp "$selected_backup" /etc/ufw/user.rules
          
          # Reload and enable UFW
          ufw --force reset
          ufw --force enable
          
          log "UFW configuration restored from $selected_backup"
          dialog_info "Backup Restored" "The UFW configuration has been restored from the selected backup."
          ;;
        iptables)
          if [ -z "$iptables_backups" ]; then
            dialog_info "No iptables Backups" "No iptables backup files found."
            log "No iptables backup files found"
            return
          fi
          
          # Build menu options
          local backup_options=()
          local counter=0
          
          while read -r backup_file; do
            local backup_date=$(basename "$backup_file" | sed 's/iptables_backup_\(.*\)\.rules/\1/')
            backup_date=$(date -d "${backup_date:0:8} ${backup_date:8:2}:${backup_date:10:2}:${backup_date:12:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$backup_date")
            backup_options+=("$backup_file" "Backup from $backup_date")
            counter=$((counter + 1))
          done <<< "$iptables_backups"
          
          # Let user choose a backup file
          local selected_backup=$(dialog_menu "Select Backup" "Choose an iptables backup to restore:" "${backup_options[@]}")
          
if ! dialog_confirm "Restore Backup" "Are you sure you want to restore the iptables rules from this backup?\n\nThis will overwrite your current firewall rules."; then
            log "Backup restoration cancelled"
            return
          fi
          
          # Restore the rules
          iptables-restore < "$selected_backup"
          
          log "iptables rules restored from $selected_backup"
          dialog_info "Backup Restored" "The iptables rules have been restored from the selected backup."
          ;;
      esac
      ;;
  esac
}

# Function for installing firewall software
install_firewall() {
  log "Firewall software installation started"
  
  local firewall_option=$(dialog_menu "Install Firewall" "Choose a firewall to install:" \
    "ufw" "UFW (Uncomplicated Firewall)" \
    "iptables" "iptables (low-level firewall)" \
    "firewalld" "firewalld (dynamic firewall)" \
    "fail2ban" "Fail2Ban (intrusion prevention)" \
    "back" "Back to firewall menu")
  
  if [ -z "$firewall_option" ] || [ "$firewall_option" = "back" ]; then
    log "Firewall option selection cancelled"
    return
  fi
  
  case $firewall_option in
    ufw)
      # Install UFW
      if command -v ufw &> /dev/null; then
        dialog_info "Already Installed" "UFW is already installed on this system."
        log "UFW is already installed"
        return
      fi
      
      if dialog_confirm "Install UFW" "Do you want to install UFW (Uncomplicated Firewall)?"; then
        apt update
        apt install -y ufw
        track_installed_package "ufw"
        
        log "UFW installed"
        dialog_info "UFW Installed" "UFW has been installed on this system."
        
        # Ask if user wants to enable UFW
        if dialog_confirm "Enable UFW" "Do you want to enable UFW with default settings?\n\nThis will allow outgoing traffic and deny incoming traffic."; then
          # First, ensure SSH access is allowed
          if dialog_confirm "Allow SSH" "Do you want to allow SSH access (recommended)?"; then
            local ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
            if [ -z "$ssh_port" ]; then
              ssh_port="22"
            fi
            
            ufw allow $ssh_port/tcp
            log "UFW rule added: allow SSH on port $ssh_port/tcp"
          fi
          
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          
          log "UFW enabled with default settings"
          dialog_info "UFW Enabled" "UFW has been enabled with default settings."
        fi
      else
        log "UFW installation cancelled"
      fi
      ;;
    iptables)
      # Install iptables
      if command -v iptables &> /dev/null; then
        dialog_info "Already Installed" "iptables is already installed on this system."
        log "iptables is already installed"
        return
      fi
      
      if dialog_confirm "Install iptables" "Do you want to install iptables?"; then
        apt update
        apt install -y iptables iptables-persistent
        track_installed_package "iptables"
        track_installed_package "iptables-persistent"
        
        log "iptables installed"
        dialog_info "iptables Installed" "iptables has been installed on this system."
        
        # Ask if user wants to set up basic rules
        if dialog_confirm "Basic Rules" "Do you want to set up basic iptables rules?\n\nThis will allow established connections, SSH, and block everything else."; then
          # Create basic ruleset
          iptables -F
          iptables -X
          iptables -t nat -F
          iptables -t nat -X
          iptables -t mangle -F
          iptables -t mangle -X
          
          # Default policies
          iptables -P INPUT DROP
          iptables -P FORWARD DROP
          iptables -P OUTPUT ACCEPT
          
          # Allow loopback
          iptables -A INPUT -i lo -j ACCEPT
          iptables -A OUTPUT -o lo -j ACCEPT
          
          # Allow established connections
          iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
          
          # Allow SSH
          local ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
          if [ -z "$ssh_port" ]; then
            ssh_port="22"
          fi
          
          iptables -A INPUT -p tcp --dport $ssh_port -j ACCEPT
          
          # Save the rules
          mkdir -p /etc/iptables
          iptables-save > /etc/iptables/rules.v4
          
          log "Basic iptables rules set up"
          dialog_info "Rules Set Up" "Basic iptables rules have been set up."
        fi
      else
        log "iptables installation cancelled"
      fi
      ;;
    firewalld)
      # Install firewalld
      if command -v firewall-cmd &> /dev/null; then
        dialog_info "Already Installed" "firewalld is already installed on this system."
        log "firewalld is already installed"
        return
      fi
      
      if dialog_confirm "Install firewalld" "Do you want to install firewalld?\n\nThis will replace any existing UFW or iptables configuration."; then
        apt update
        apt install -y firewalld
        track_installed_package "firewalld"
        
        # Disable UFW if installed
        if command -v ufw &> /dev/null; then
          ufw disable
        fi
        
        # Start and enable firewalld
        systemctl start firewalld
        systemctl enable firewalld
        
        # Allow SSH
        local ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        if [ -z "$ssh_port" ]; then
          ssh_port="22"
        fi
        
        firewall-cmd --permanent --add-port=$ssh_port/tcp
        firewall-cmd --reload
        
        log "firewalld installed and configured"
        dialog_info "firewalld Installed" "firewalld has been installed and configured to allow SSH."
      else
        log "firewalld installation cancelled"
      fi
      ;;
    fail2ban)
      # Install Fail2Ban
      if command -v fail2ban-client &> /dev/null; then
        dialog_info "Already Installed" "Fail2Ban is already installed on this system."
        log "Fail2Ban is already installed"
        return
      fi
      
      if dialog_confirm "Install Fail2Ban" "Do you want to install Fail2Ban for intrusion prevention?"; then
        apt update
        apt install -y fail2ban
        track_installed_package "fail2ban"
        
        # Create a basic configuration
        mkdir -p /etc/fail2ban/jail.d
        
        cat > /etc/fail2ban/jail.d/defaults-debian.conf << EOL
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOL
        
        # Start and enable Fail2Ban
        systemctl start fail2ban
        systemctl enable fail2ban
        
        log "Fail2Ban installed and configured"
        dialog_info "Fail2Ban Installed" "Fail2Ban has been installed and configured to protect SSH."
      else
        log "Fail2Ban installation cancelled"
      fi
      ;;
  esac
}

#######################################
# DISK MANAGEMENT FUNCTIONS
#######################################

# Function for disk information
disk_info() {
  log "Disk information started"
  
  local disk_command="lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,UUID,LABEL -p"
  local disk_output=$(eval "$disk_command")
  
  # Create JSON data for the table
  local disk_data='{
    "Disk Information": [
      {"Command": "lsblk output", "Value": "'"$disk_output"'"}
    ]
  }'
  
  # Format disk info table
  local formatted_disk=$(python3 -c "
import json
from tabulate import tabulate
data = json.loads('$disk_data')
print(tabulate(data['Disk Information'], headers='keys', tablefmt='grid'))
")
  
  # Add more detailed information if available
  local mounted_info=""
  mounted_info+="MOUNTED FILESYSTEMS (df -h):\n"
  mounted_info+=$(df -h)
  
  local disk_usage=$(du -sh / 2>/dev/null || echo "N/A (permission denied)")
  
  local smart_info=""
  if command -v smartctl &> /dev/null; then
    smart_info+="\n\nS.M.A.R.T. STATUS OF PHYSICAL DISKS:\n"
    for disk in $(lsblk -d -n -o NAME); do
      if [[ $disk == sd* || $disk == nvme* || $disk == hd* ]]; then
        smart_info+="Disk /dev/$disk: "
        smart_info+=$(smartctl -H /dev/$disk 2>/dev/null | grep "SMART overall-health" || echo "S.M.A.R.T. not available")
        smart_info+="\n"
      fi
    done
  fi
  
  # Show disk information
  dialog_info "Disk Information" "$disk_output\n\n$mounted_info\n\nTotal disk usage for root filesystem: $disk_usage $smart_info"
}

# Function for disk partitioning
partition_disk() {
  log "Disk partitioning started"
  
  # Get list of physical disks
  local disks=$(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr")
  
  if [ -z "$disks" ]; then
    dialog_info "No Disks" "No physical disks found."
    log "No physical disks found"
    return
  fi
  
  # Format the disk list
  local disk_list=""
  while read -r line; do
    local name=$(echo "$line" | awk '{print $1}')
    local size=$(echo "$line" | awk '{print $2}')
    local model=$(echo "$line" | awk '{$1=""; $2=""; print $0}' | sed 's/^[ \t]*//')
    disk_list+="/dev/$name ($size"
    if [ ! -z "$model" ]; then
      disk_list+=" - $model"
    fi
    disk_list+=")\n"
  done <<< "$disks"
  
  # Ask for confirmation with clear warning
  if ! dialog_confirm "Disk Partitioning" "WARNING: Disk partitioning can lead to DATA LOSS.\n\nAvailable disks:\n$disk_list\n\nDo you want to proceed with disk partitioning?"; then
    log "Disk partitioning cancelled by user"
    return
  fi
  
  # Choose partitioning tool
  local tool=$(dialog_menu "Partitioning Tool" "Choose a partitioning tool:" \
    "parted" "GNU Parted (command-line)" \
    "fdisk" "fdisk (command-line)" \
    "cfdisk" "cfdisk (ncurses interface)" \
    "back" "Cancel partitioning")
  
  if [ -z "$tool" ] || [ "$tool" = "back" ]; then
    log "Partitioning tool selection cancelled"
    return
  fi
  
  # Check if tool is installed
  if ! command -v $tool &> /dev/null; then
    if dialog_confirm "Install $tool" "$tool is not installed. Would you like to install it?"; then
      apt update
      apt install -y $tool
      track_installed_package "$tool"
      log "$tool installed"
    else
      dialog_info "$tool" "$tool is required for partitioning."
      log "$tool installation cancelled"
      return
    fi
  fi
  
  # Choose disk to partition
  local disk_options=()
  
  while read -r line; do
    local name=$(echo "$line" | awk '{print $1}')
    local size=$(echo "$line" | awk '{print $2}')
    local model=$(echo "$line" | awk '{$1=""; $2=""; print $0}' | sed 's/^[ \t]*//')
    disk_options+=("/dev/$name" "$size - $model")
  done <<< "$disks"
  
  local selected_disk=$(dialog_menu "Select Disk" "Choose a disk to partition:" "${disk_options[@]}")
  
  if [ -z "$selected_disk" ]; then
    log "Disk selection cancelled"
    return
  fi
  
  # Final warning
  if ! dialog_confirm "FINAL WARNING" "You are about to partition $selected_disk.\n\nTHIS WILL DESTROY ALL DATA ON THE DISK.\n\nAre you absolutely sure you want to proceed?"; then
    log "Disk partitioning cancelled at final warning"
    return
  fi
  
  # Exit dialog temporarily to run the tool
  clear
  echo -e "${YELLOW}Starting $tool for $selected_disk.${NC}"
  echo -e "${RED}WARNING: Be careful with disk partitioning!${NC}"
  echo
  
  # Run the selected tool
  case $tool in
    parted)
      parted "$selected_disk"
      ;;
    fdisk)
      fdisk "$selected_disk"
      ;;
    cfdisk)
      cfdisk "$selected_disk"
      ;;
  esac
  
  # Wait for user to acknowledge
  echo
  echo -e "${YELLOW}Partitioning completed. Press Enter to continue...${NC}"
  read
  
  log "Disk $selected_disk partitioned using $tool"
  
  # Ask if user wants to create filesystems
  if dialog_confirm "Create Filesystems" "Do you want to create filesystems on the newly created partitions?"; then
    format_partition
  fi
}

# Function for formatting partitions
format_partition() {
  log "Partition formatting started"
  
  # Get list of partitions
  local partitions=$(lsblk -n -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v "loop" | grep "part" | grep -v -E '[[:space:]]/$|[[:space:]]/boot|[[:space:]]/home|[[:space:]]/var|[[:space:]]/usr|[[:space:]]/etc')
  
  if [ -z "$partitions" ]; then
    dialog_info "No Partitions" "No suitable partitions found for formatting."
    log "No suitable partitions found"
    return
  fi
  
  # Format the partition list and create options
  local partition_options=()
  
  while read -r line; do
    local name=$(echo "$line" | awk '{print $1}')
    local size=$(echo "$line" | awk '{print $2}')
    local mountpoint=$(echo "$line" | awk '{print $4}')
    
    # Skip partitions that are mounted to important system directories
    if [[ "$mountpoint" == "/" || "$mountpoint" == "/boot" || "$mountpoint" == "/home" || 
          "$mountpoint" == "/var" || "$mountpoint" == "/usr" || "$mountpoint" == "/etc" ]]; then
      continue
    fi
    
    local desc="$size"
    if [ ! -z "$mountpoint" ]; then
      desc+=" - Mounted at $mountpoint"
    else
      desc+=" - Not mounted"
    fi
    
    partition_options+=("/dev/$name" "$desc")
  done <<< "$partitions"
  
  if [ ${#partition_options[@]} -eq 0 ]; then
    dialog_info "No Partitions" "No suitable partitions found for formatting."
    log "No suitable partitions found"
    return
  fi
  
  # Choose partition to format
  local selected_partition=$(dialog_menu "Select Partition" "Choose a partition to format:" "${partition_options[@]}")
  
  if [ -z "$selected_partition" ]; then
    log "Partition selection cancelled"
    return
  fi
  
  # Check if partition is mounted
  local is_mounted=0
  if mount | grep -q "$selected_partition"; then
    is_mounted=1
  fi
  
  if [ $is_mounted -eq 1 ]; then
    if ! dialog_confirm "Unmount Partition" "The partition $selected_partition is currently mounted and must be unmounted before formatting.\n\nDo you want to unmount it?"; then
      log "Partition unmounting cancelled"
      return
    fi
    
    umount "$selected_partition"
    if [ $? -ne 0 ]; then
      dialog_info "Unmount Failed" "Failed to unmount $selected_partition. It may be in use by the system."
      log "Failed to unmount $selected_partition"
      return
    fi
  fi
  
  # Choose filesystem type
  local fs_type=$(dialog_menu "Filesystem Type" "Choose a filesystem type for $selected_partition:" \
    "ext4" "Extended Filesystem (ext4) - Standard Linux filesystem" \
    "xfs" "XFS - High performance filesystem" \
    "btrfs" "Btrfs - Modern copy-on-write filesystem" \
    "swap" "Linux swap area" \
    "ntfs" "NTFS - Windows compatible filesystem" \
    "vfat" "FAT32 - Compatible with most operating systems" \
    "exfat" "exFAT - Compatible with most operating systems, supports >4GB files" \
    "back" "Cancel formatting")
  
  if [ -z "$fs_type" ] || [ "$fs_type" = "back" ]; then
    log "Filesystem type selection cancelled"
    return
  fi
  
  # Check if required tools are installed
  local tool_missing=0
  local needed_pkg=""
  
  case $fs_type in
    ext4)
      if ! command -v mkfs.ext4 &> /dev/null; then
        tool_missing=1
        needed_pkg="e2fsprogs"
      fi
      ;;
    xfs)
      if ! command -v mkfs.xfs &> /dev/null; then
        tool_missing=1
        needed_pkg="xfsprogs"
      fi
      ;;
    btrfs)
      if ! command -v mkfs.btrfs &> /dev/null; then
        tool_missing=1
        needed_pkg="btrfs-progs"
      fi
      ;;
    swap)
      if ! command -v mkswap &> /dev/null; then
        tool_missing=1
        needed_pkg="util-linux"
      fi
      ;;
    ntfs)
      if ! command -v mkfs.ntfs &> /dev/null; then
        tool_missing=1
        needed_pkg="ntfs-3g"
      fi
      ;;
    vfat)
      if ! command -v mkfs.vfat &> /dev/null; then
        tool_missing=1
        needed_pkg="dosfstools"
      fi
      ;;
    exfat)
      if ! command -v mkfs.exfat &> /dev/null; then
        tool_missing=1
        needed_pkg="exfat-utils"
      fi
      ;;
  esac
  
  if [ $tool_missing -eq 1 ]; then
    if dialog_confirm "Install Required Tools" "The required tools for $fs_type formatting are not installed. Would you like to install $needed_pkg?"; then
      apt update
      apt install -y $needed_pkg
      track_installed_package "$needed_pkg"
      log "$needed_pkg installed"
    else
      dialog_info "Tools Required" "The required tools are needed for formatting."
      log "Required tools installation cancelled"
      return
    fi
  fi
  
  # Ask for filesystem label
  local fs_label=$(dialog_input "Filesystem Label" "Enter a label for the filesystem (optional):" "")
  
  # Final confirmation
  if ! dialog_confirm "Format Partition" "You are about to format $selected_partition with $fs_type filesystem.\n\nTHIS WILL DESTROY ALL DATA ON THE PARTITION.\n\nAre you sure you want to proceed?"; then
    log "Partition formatting cancelled"
    return
  fi
  
  # Format the partition
  local format_command=""
  local format_options=""
  
  if [ ! -z "$fs_label" ]; then
    case $fs_type in
      ext4)
        format_options="-L \"$fs_label\""
        ;;
      xfs)
        format_options="-L \"$fs_label\""
        ;;
      btrfs)
        format_options="-L \"$fs_label\""
        ;;
      swap)
        format_options="-L \"$fs_label\""
        ;;
      ntfs)
        format_options="-L \"$fs_label\""
        ;;
      vfat)
        format_options="-n \"$fs_label\""
        ;;
      exfat)
        format_options="-n \"$fs_label\""
        ;;
    esac
  fi
  
  case $fs_type in
    swap)
      format_command="mkswap $format_options $selected_partition"
      ;;
    *)
      format_command="mkfs.$fs_type $format_options $selected_partition"
      ;;
  esac
  
  # Show progress
  (
    echo "10"; echo "XXX"; echo "Preparing to format partition..."; echo "XXX"
    sleep 1
    
    echo "50"; echo "XXX"; echo "Formatting $selected_partition with $fs_type..."; echo "XXX"
    eval "$format_command" > /tmp/format_output.log 2>&1
    local format_status=$?
    
    echo "90"; echo "XXX"; echo "Finalizing..."; echo "XXX"
    sleep 1
    
    echo "100"; echo "XXX"; echo "Format completed."; echo "XXX"
    
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Formatting Partition" --gauge "Please wait..." 10 70 0
  
  local format_output=$(cat /tmp/format_output.log)
  rm -f /tmp/format_output.log
  
  # Check if formatting was successful
  if [ $format_status -eq 0 ]; then
    log "Partition $selected_partition formatted with $fs_type"
    
    local mount_msg="The partition has been successfully formatted with $fs_type filesystem."
    
    # For swap, ask if user wants to enable it
    if [ "$fs_type" = "swap" ]; then
      if dialog_confirm "Enable Swap" "Do you want to enable the newly created swap partition?"; then
        swapon "$selected_partition"
        
        # Add to fstab
        if dialog_confirm "Add to fstab" "Do you want to add the swap partition to /etc/fstab for automatic mounting at boot?"; then
          local uuid=$(blkid -s UUID -o value "$selected_partition")
          echo "UUID=$uuid none swap sw 0 0" >> /etc/fstab
          log "Swap partition added to fstab"
        fi
        
        mount_msg+="The swap partition has been enabled."
      fi
    else
      # For other filesystems, ask if user wants to mount it
      if dialog_confirm "Mount Partition" "Do you want to mount the newly formatted partition?"; then
        # Create mount point
        local mount_point=$(dialog_input "Mount Point" "Enter the mount point for this partition:" "/mnt/data")
        
        if [ -z "$mount_point" ]; then
          log "Mount point input cancelled"
          dialog_info "Format Complete" "$mount_msg"
          return
        fi
        
        # Create the directory if it doesn't exist
        mkdir -p "$mount_point"
        
        # Mount the partition
        mount "$selected_partition" "$mount_point"
        
        # Add to fstab
        if dialog_confirm "Add to fstab" "Do you want to add this mount point to /etc/fstab for automatic mounting at boot?"; then
          local uuid=$(blkid -s UUID -o value "$selected_partition")
          local fstab_options="defaults"
          
          case $fs_type in
            ext4|xfs|btrfs)
              fstab_options="defaults,noatime"
              ;;
            ntfs)
              fstab_options="defaults,windows_names,locale=en_US.utf8"
              ;;
            vfat|exfat)
              fstab_options="defaults,uid=1000,gid=1000,umask=022"
              ;;
          esac
          
          echo "UUID=$uuid $mount_point $fs_type $fstab_options 0 2" >> /etc/fstab
          log "Partition added to fstab at mount point $mount_point"
        fi
        
        mount_msg+="\n\nThe partition has been mounted at $mount_point."
      fi
    fi
    
    dialog_info "Format Complete" "$mount_msg"
  else
    log "Failed to format partition $selected_partition: $format_output"
    dialog_info "Format Failed" "Failed to format the partition. Please check the output for details:\n\n$format_output"
  fi
}

# Function for mounting partitions
mount_partition() {
  log "Mount partition started"
  
  # Get list of unmounted partitions
  local partitions=$(lsblk -n -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep "part" | grep -v -e "swap" -e "crypto" | grep -v -E '[[:space:]]/$|[[:space:]]/boot|[[:space:]]/home|[[:space:]]/var|[[:space:]]/usr|[[:space:]]/etc')
  
  # Filter out already mounted partitions
  local unmounted_partitions=""
  while read -r line; do
    local mountpoint=$(echo "$line" | awk '{print $5}')
    if [ -z "$mountpoint" ]; then
      unmounted_partitions+="$line\n"
    fi
  done <<< "$partitions"
  
  if [ -z "$unmounted_partitions" ]; then
    dialog_info "No Unmounted Partitions" "No unmounted partitions found."
    log "No unmounted partitions found"
    return
  fi
  
  # Format the partition list and create options
  local partition_options=()
  
  while read -r line; do
    local name=$(echo "$line" | awk '{print $1}')
    local size=$(echo "$line" | awk '{print $2}')
    local fstype=$(echo "$line" | awk '{print $4}')
    
    if [ -z "$fstype" ] || [ "$fstype" = "swap" ]; then
      continue
    fi
    
    partition_options+=("/dev/$name" "$size - $fstype filesystem")
  done <<< "$unmounted_partitions"
  
  if [ ${#partition_options[@]} -eq 0 ]; then
    dialog_info "No Mountable Partitions" "No mountable partitions found."
    log "No mountable partitions found"
    return
  fi
  
  # Choose partition to mount
  local selected_partition=$(dialog_menu "Select Partition" "Choose a partition to mount:" "${partition_options[@]}")
  
  if [ -z "$selected_partition" ]; then
    log "Partition selection cancelled"
    return
  fi
  
  # Get filesystem type
  local fstype=$(lsblk -n -o FSTYPE "$selected_partition")
  
  if [ -z "$fstype" ]; then
    dialog_info "No Filesystem" "No filesystem detected on $selected_partition. Please format the partition first."
    log "No filesystem detected on $selected_partition"
    return
  fi
  
  # Create mount point
  local mount_point=$(dialog_input "Mount Point" "Enter the mount point for $selected_partition:" "/mnt/data")
  
  if [ -z "$mount_point" ]; then
    log "Mount point input cancelled"
    return
  fi
  
  # Create the directory if it doesn't exist
  mkdir -p "$mount_point"
  
  # Mount options
  local mount_options=""
  
  case $fstype in
    ntfs)
      # Check if ntfs-3g is installed
      if ! command -v ntfs-3g &> /dev/null; then
        if dialog_confirm "Install ntfs-3g" "ntfs-3g is required to mount NTFS partitions. Do you want to install it?"; then
          apt update
          apt install -y ntfs-3g
          track_installed_package "ntfs-3g"
          log "ntfs-3g installed"
        else
          dialog_info "ntfs-3g Required" "ntfs-3g is required to mount NTFS partitions."
          log "ntfs-3g installation cancelled"
          return
        fi
      fi
      mount_options="-o windows_names,locale=en_US.utf8"
      ;;
    vfat|exfat)
      mount_options="-o uid=1000,gid=1000,umask=022"
      ;;
  esac
  
  # Mount the partition
  local mount_command="mount $mount_options $selected_partition $mount_point"
  eval "$mount_command"
  
  if [ $? -eq 0 ]; then
    log "Partition $selected_partition mounted at $mount_point"
    
    # Add to fstab
    if dialog_confirm "Add to fstab" "Do you want to add this mount point to /etc/fstab for automatic mounting at boot?"; then
      local uuid=$(blkid -s UUID -o value "$selected_partition")
      local fstab_options="defaults"
      
      case $fstype in
        ext4|xfs|btrfs)
          fstab_options="defaults,noatime"
          ;;
        ntfs)
          fstab_options="defaults,windows_names,locale=en_US.utf8"
          ;;
        vfat|exfat)
          fstab_options="defaults,uid=1000,gid=1000,umask=022"
          ;;
      esac
      
      echo "UUID=$uuid $mount_point $fstype $fstab_options 0 2" >> /etc/fstab
      log "Partition added to fstab at mount point $mount_point"
      
      dialog_info "Mount Complete" "The partition $selected_partition has been mounted at $mount_point and added to /etc/fstab for automatic mounting at boot."
    else
      dialog_info "Mount Complete" "The partition $selected_partition has been mounted at $mount_point."
    fi
  else
    log "Failed to mount partition $selected_partition at $mount_point"
    dialog_info "Mount Failed" "Failed to mount the partition $selected_partition at $mount_point.\n\nPlease check if the filesystem is supported and the mount point is valid."
  fi
}

# Function for unmounting partitions
unmount_partition() {
  log "Unmount partition started"
  
  # Get list of mounted partitions
  local partitions=$(lsblk -n -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep "part" | grep -v "swap" | grep -v -E '^(sd|nvme|mmc)[a-z]+$' | grep -v -E '[[:space:]]/$|[[:space:]]/boot|[[:space:]]/boot/efi')
  
  # Filter out partitions that are not currently mounted
  local mounted_partitions=""
  while read -r line; do
    local mountpoint=$(echo "$line" | awk '{print $5}')
    if [ ! -z "$mountpoint" ]; then
      mounted_partitions+="$line\n"
    fi
  done <<< "$partitions"
  
  if [ -z "$mounted_partitions" ]; then
    dialog_info "No Mounted Partitions" "No mounted partitions found that can be safely unmounted."
    log "No mounted partitions found"
    return
  fi
  
  # Format the partition list and create options
  local partition_options=()
  
  while read -r line; do
    local name=$(echo "$line" | awk '{print $1}')
    local size=$(echo "$line" | awk '{print $2}')
    local fstype=$(echo "$line" | awk '{print $4}')
    local mountpoint=$(echo "$line" | awk '{print $5}')
    
    # Skip system partitions
    if [[ "$mountpoint" == "/" || "$mountpoint" == "/boot" || "$mountpoint" == "/boot/efi" || 
          "$mountpoint" == "/var" || "$mountpoint" == "/usr" || "$mountpoint" == "/etc" || 
          "$mountpoint" == "/home" ]]; then
      continue
    fi
    
    partition_options+=("/dev/$name" "$size - Mounted at $mountpoint")
  done <<< "$mounted_partitions"
  
  if [ ${#partition_options[@]} -eq 0 ]; then
    dialog_info "No Unmountable Partitions" "No mounted partitions found that can be safely unmounted."
    log "No safely unmountable partitions found"
    return
  fi
  
  # Choose partition to unmount
  local selected_partition=$(dialog_menu "Select Partition" "Choose a partition to unmount:" "${partition_options[@]}")
  
  if [ -z "$selected_partition" ]; then
    log "Partition selection cancelled"
    return
  fi
  
  # Get the mount point
  local mount_point=$(findmnt -n -o TARGET "$selected_partition")
  
  # Check if any processes are using the mount point
  local processes=$(lsof "$mount_point" 2>/dev/null)
  
  if [ ! -z "$processes" ]; then
    if ! dialog_confirm "Processes Using Mount" "There are processes using this mount point. Force unmount?"; then
      log "Unmount cancelled due to active processes"
      return
    fi
  fi
  
  # Unmount the partition
  umount "$selected_partition"
  
  if [ $? -eq 0 ]; then
    log "Partition $selected_partition unmounted from $mount_point"
    
    # Ask if user wants to remove from fstab
    if dialog_confirm "Remove from fstab" "Do you want to remove this mount point from /etc/fstab?"; then
      # Create backup
      cp /etc/fstab "$BACKUP_DIR/disk/fstab.backup.$(date +%Y%m%d%H%M%S)"
      
      # Get UUID
      local uuid=$(blkid -s UUID -o value "$selected_partition")
      
      # Remove from fstab
      if [ ! -z "$uuid" ]; then
        sed -i "/UUID=$uuid/d" /etc/fstab
      else
        sed -i "\|$selected_partition|d" /etc/fstab
        sed -i "\|$mount_point|d" /etc/fstab
      fi
      
      log "Partition removed from fstab"
      dialog_info "Unmount Complete" "The partition $selected_partition has been unmounted from $mount_point and removed from /etc/fstab."
    else
      dialog_info "Unmount Complete" "The partition $selected_partition has been unmounted from $mount_point."
    fi
  else
    log "Failed to unmount partition $selected_partition from $mount_point"
    
    if dialog_confirm "Force Unmount" "Failed to unmount. Do you want to force unmount (umount -f)?"; then
      umount -f "$selected_partition"
      
      if [ $? -eq 0 ]; then
        log "Partition $selected_partition force unmounted from $mount_point"
        dialog_info "Force Unmount Complete" "The partition $selected_partition has been force unmounted from $mount_point."
      else
        log "Failed to force unmount partition $selected_partition from $mount_point"
        dialog_info "Unmount Failed" "Failed to force unmount the partition. It might be in use by the system."
      fi
    else
      dialog_info "Unmount Failed" "Failed to unmount the partition. It might be in use by the system."
    fi
  fi
}

# Function for checking disk health
check_disk_health() {
  log "Disk health check started"
  
  # Check if smartmontools is installed
  if ! command -v smartctl &> /dev/null; then
    if dialog_confirm "Install smartmontools" "smartmontools is needed for disk health checking. Would you like to install it?"; then
      apt update
      apt install -y smartmontools
      track_installed_package "smartmontools"
      log "smartmontools installed"
    else
      dialog_info "smartmontools" "smartmontools is required for disk health checking."
      log "smartmontools installation cancelled"
      return
    fi
  fi
  
  # Get list of physical disks
  local disks=$(lsblk -d -n -o NAME | grep -v "loop" | grep -v "sr")
  
  if [ -z "$disks" ]; then
    dialog_info "No Disks" "No physical disks found."
    log "No physical disks found"
    return
  fi
  
  # Format the disk list and create options
  local disk_options=()
  
  while read -r name; do
    local model=$(lsblk -d -n -o MODEL "/dev/$name" 2>/dev/null || echo "Unknown")
    local size=$(lsblk -d -n -o SIZE "/dev/$name" 2>/dev/null || echo "Unknown")
    
    disk_options+=("/dev/$name" "$size - $model")
  done <<< "$disks"
  
  # Choose disk to check
  local selected_disk=$(dialog_menu "Select Disk" "Choose a disk to check:" "${disk_options[@]}")
  
  if [ -z "$selected_disk" ]; then
    log "Disk selection cancelled"
    return
  fi
  
  # Check if SMART is available
  if ! smartctl -i "$selected_disk" | grep -q "SMART support is: Available"; then
    dialog_info "SMART Not Available" "SMART is not available on this disk or device.\n\nOnly limited information will be shown."
    log "SMART not available on $selected_disk"
    
    # Show basic info anyway
    local disk_info=$(smartctl -i "$selected_disk" 2>/dev/null || echo "Unable to get disk information")
    
    dialog_info "Disk Info" "Basic disk information for $selected_disk:\n\n$disk_info"
    return
  fi
  
  # Check disk health (short test)
  (
    echo "10"; echo "XXX"; echo "Getting disk information..."; echo "XXX"
    local disk_info=$(smartctl -i "$selected_disk" 2>/dev/null)
    
    echo "30"; echo "XXX"; echo "Checking SMART status..."; echo "XXX"
    local smart_status=$(smartctl -H "$selected_disk" 2>/dev/null)
    
    echo "50"; echo "XXX"; echo "Getting SMART attributes..."; echo "XXX"
    local smart_attrs=$(smartctl -A "$selected_disk" 2>/dev/null)
    
    echo "70"; echo "XXX"; echo "Checking for errors..."; echo "XXX"
    local error_log=$(smartctl -l error "$selected_disk" 2>/dev/null)
    
    echo "90"; echo "XXX"; echo "Finalizing report..."; echo "XXX"
    
    # Save results to a file
    echo "Disk Information for $selected_disk" > /tmp/disk_health.txt
    echo "=======================================" >> /tmp/disk_health.txt
    echo "$disk_info" >> /tmp/disk_health.txt
    echo "" >> /tmp/disk_health.txt
    echo "SMART Status:" >> /tmp/disk_health.txt
    echo "=======================================" >> /tmp/disk_health.txt
    echo "$smart_status" >> /tmp/disk_health.txt
    echo "" >> /tmp/disk_health.txt
    echo "SMART Attributes:" >> /tmp/disk_health.txt
    echo "=======================================" >> /tmp/disk_health.txt
    echo "$smart_attrs" >> /tmp/disk_health.txt
    echo "" >> /tmp/disk_health.txt
    echo "Error Log:" >> /tmp/disk_health.txt
    echo "=======================================" >> /tmp/disk_health.txt
    echo "$error_log" >> /tmp/disk_health.txt
    
    echo "100"; echo "XXX"; echo "Disk health check completed."; echo "XXX"
    
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Checking Disk Health" --gauge "Please wait..." 10 70 0
  
  # Check if the overall health status is OK
  local health_status=$(smartctl -H "$selected_disk" | grep "overall-health" | awk '{print $NF}')
  
  # Create a summary
  local summary=""
  
  if [ "$health_status" = "PASSED" ]; then
    summary="✅ Overall health status: PASSED\n\n"
  else
    summary="⚠️ Overall health status: $health_status\n\n"
  fi
  
  # Add important SMART attributes to the summary
  summary+="Important SMART attributes:\n"
  
  # Reallocated sectors
  local reallocated=$(smartctl -A "$selected_disk" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
  if [ ! -z "$reallocated" ]; then
    if [ "$reallocated" -eq 0 ]; then
      summary+="✅ Reallocated Sectors: $reallocated\n"
    else
      summary+="⚠️ Reallocated Sectors: $reallocated (should be 0)\n"
    fi
  fi
  
  # Pending sectors
  local pending=$(smartctl -A "$selected_disk" | grep "Current_Pending_Sector" | awk '{print $10}')
  if [ ! -z "$pending" ]; then
    if [ "$pending" -eq 0 ]; then
      summary+="✅ Pending Sectors: $pending\n"
    else
      summary+="⚠️ Pending Sectors: $pending (should be 0)\n"
    fi
  fi
  
  # Power on hours
  local power_hours=$(smartctl -A "$selected_disk" | grep "Power_On_Hours" | awk '{print $10}')
  if [ ! -z "$power_hours" ]; then
    summary+="ℹ️ Power On Hours: $power_hours\n"
  fi
  
  # Temperature
  local temp=$(smartctl -A "$selected_disk" | grep "Temperature_Celsius" | awk '{print $10}')
  if [ ! -z "$temp" ]; then
    if [ "$temp" -lt 50 ]; then
      summary+="✅ Temperature: $temp°C\n"
    elif [ "$temp" -lt 60 ]; then
      summary+="⚠️ Temperature: $temp°C (high)\n"
    else
      summary+="❌ Temperature: $temp°C (critical)\n"
    fi
  fi
  
  # Add error count
  local error_count=$(smartctl -l error "$selected_disk" | grep -c "Error")
  if [ "$error_count" -eq 0 ]; then
    summary+="✅ No errors found in error log\n"
  else
    summary+="⚠️ $error_count errors found in error log\n"
  fi
  
  summary+="\nFull disk health report has been saved to /tmp/disk_health.txt"
  
  # Backup the report
  mkdir -p "$BACKUP_DIR/disk"
  cp /tmp/disk_health.txt "$BACKUP_DIR/disk/health_${selected_disk//\//_}_$(date +%Y%m%d%H%M%S).txt"
  
  # Show summary
  dialog_info "Disk Health Summary" "$summary"
  
  # Ask if user wants to run a self-test
  if dialog_confirm "Self-Test" "Do you want to run a SMART self-test on the disk?\n\nThis may take several minutes."; then
    local test_type=$(dialog_menu "Test Type" "Choose the type of test to run:" \
      "short" "Short test (usually takes 2 minutes)" \
      "long" "Extended/Long test (can take hours)" \
      "back" "Cancel")
    
    if [ -z "$test_type" ] || [ "$test_type" = "back" ]; then
      log "Self-test cancelled"
      return
    fi
    
    # Run the test
    (
      echo "0"; echo "XXX"; echo "Starting $test_type self-test..."; echo "XXX"
      smartctl -t $test_type "$selected_disk" > /dev/null
      
      # Get estimated completion time
      local test_time=$(smartctl -c "$selected_disk" | grep "Short self-test" | awk '{print $3}')
      if [ "$test_type" = "long" ]; then
        test_time=$(smartctl -c "$selected_disk" | grep "Extended self-test" | awk '{print $4}')
      fi
      
      echo "10"; echo "XXX"; echo "Test in progress, estimated time: $test_time minutes..."; echo "XXX"
      
      # We can't actually wait for it to complete, so we'll just simulate progress
      local progress=10
      local step=$((90 / $test_time))
      
      for ((i=1; i<=$test_time; i++)); do
        sleep 60
        progress=$((progress + step))
        if [ $progress -gt 95 ]; then
          progress=95
        fi
        echo "$progress"; echo "XXX"; echo "Test in progress: $i/$test_time minutes elapsed..."; echo "XXX"
      done
      
      # Final check
      echo "98"; echo "XXX"; echo "Getting test results..."; echo "XXX"
      local results=$(smartctl -l selftest "$selected_disk")
      
      # Save results
      echo "" >> /tmp/disk_health.txt
      echo "Self-Test Results:" >> /tmp/disk_health.txt
      echo "=======================================" >> /tmp/disk_health.txt
      echo "$results" >> /tmp/disk_health.txt
      
      echo "100"; echo "XXX"; echo "Self-test completed."; echo "XXX"
      
    ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Running Self-Test" --gauge "Please wait..." 10 70 0
    
    # Show test results
    local test_result=$(smartctl -l selftest "$selected_disk" | grep -m 1 "# 1")
    local test_status=$(echo "$test_result" | awk '{print $NF}')
    
    if [[ "$test_status" == *"Completed without error"* ]]; then
      dialog_info "Self-Test Result" "✅ Self-test completed without errors.\n\nFull results have been added to the disk health report."
    else
      dialog_info "Self-Test Result" "⚠️ Self-test result: $test_status\n\nCheck the disk health report for more details."
    fi
    
    # Update backup
    cp /tmp/disk_health.txt "$BACKUP_DIR/disk/health_${selected_disk//\//_}_$(date +%Y%m%d%H%M%S).txt"
  fi
}

# Function for analyzing disk usage
analyze_disk_usage() {
  log "Disk usage analysis started"
  
  # Check if ncdu is installed
  if ! command -v ncdu &> /dev/null; then
    if dialog_confirm "Install ncdu" "ncdu (NCurses Disk Usage) is needed for disk usage analysis. Would you like to install it?"; then
      apt update
      apt install -y ncdu
      track_installed_package "ncdu"
      log "ncdu installed"
    else
      dialog_info "ncdu" "ncdu is required for detailed disk usage analysis."
      log "ncdu installation cancelled"
      return
    fi
  fi
  
  # Choose what to analyze
  local analyze_option=$(dialog_menu "Disk Usage Analysis" "Choose what to analyze:" \
    "path" "Analyze a specific path" \
    "root" "Analyze root filesystem" \
    "large" "Find large files" \
    "old" "Find old files" \
    "back" "Cancel")
  
  if [ -z "$analyze_option" ] || [ "$analyze_option" = "back" ]; then
    log "Analysis option selection cancelled"
    return
  fi
  
  case $analyze_option in
    path)
      # Analyze a specific path
      local path=$(dialog_input "Path" "Enter the path to analyze:" "/home")
      
      if [ -z "$path" ]; then
        log "Path input cancelled"
        return
      fi
      
      if [ ! -d "$path" ]; then
        dialog_info "Invalid Path" "The specified path does not exist or is not a directory."
        log "Invalid path: $path"
        return
      fi
      
      # Exit dialog temporarily to run ncdu
      clear
      echo -e "${YELLOW}Starting disk usage analyzer (ncdu) for $path.${NC}"
      echo -e "${YELLOW}Use the arrow keys to navigate, press 'q' to quit.${NC}"
      echo
      
      # Run ncdu
      ncdu "$path"
      
      # Wait for user to acknowledge
      echo
      echo -e "${YELLOW}Disk usage analysis completed. Press Enter to continue...${NC}"
      read
      
      log "Disk usage analysis completed for $path"
      ;;
    root)
      # Analyze root filesystem
      clear
      echo -e "${YELLOW}Starting disk usage analyzer (ncdu) for the root filesystem.${NC}"
      echo -e "${YELLOW}This may take a while for large filesystems.${NC}"
      echo -e "${YELLOW}Use the arrow keys to navigate, press 'q' to quit.${NC}"
      echo
      
      # Run ncdu
      ncdu /
      
      # Wait for user to acknowledge
      echo
      echo -e "${YELLOW}Disk usage analysis completed. Press Enter to continue...${NC}"
      read
      
      log "Disk usage analysis completed for root filesystem"
      ;;
    large)
      # Find large files
      local min_size=$(dialog_input "Minimum Size" "Enter the minimum file size (e.g., 100M, 1G):" "100M")
      
      if [ -z "$min_size" ]; then
        log "Minimum size input cancelled"
        return
      fi
      
      local search_path=$(dialog_input "Search Path" "Enter the path to search in:" "/")
      
      if [ -z "$search_path" ]; then
        log "Search path input cancelled"
        return
      fi
      
      if [ ! -d "$search_path" ]; then
        dialog_info "Invalid Path" "The specified path does not exist or is not a directory."
        log "Invalid path: $search_path"
        return
      fi
      
      # Create a temporary file for results
      local temp_file=$(mktemp)
      
      # Show progress
      (
        echo "0"; echo "XXX"; echo "Preparing to search for large files..."; echo "XXX"
        
        echo "10"; echo "XXX"; echo "Searching for files larger than $min_size in $search_path..."; echo "XXX"
        find "$search_path" -type f -size +$min_size -exec ls -lh {} \; > "$temp_file" 2>/dev/null
        
        echo "90"; echo "XXX"; echo "Sorting results..."; echo "XXX"
        sort -rh -k 5 "$temp_file" > "${temp_file}.sorted"
        mv "${temp_file}.sorted" "$temp_file"
        
        echo "100"; echo "XXX"; echo "Search completed."; echo "XXX"
        
      ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Finding Large Files" --gauge "Please wait..." 10 70 0
      
      # Display results
      local file_count=$(wc -l < "$temp_file")
      local results=$(head -n 100 "$temp_file")
      
      if [ "$file_count" -eq 0 ]; then
        dialog_info "No Files Found" "No files larger than $min_size found in $search_path."
      else
        local display_count=100
        if [ "$file_count" -lt 100 ]; then
          display_count="$file_count"
        fi
        
        # Create a more readable format
        local formatted_results=""
        while IFS= read -r line; do
          local perms=$(echo "$line" | awk '{print $1}')
          local size=$(echo "$line" | awk '{print $5}')
          local date=$(echo "$line" | awk '{print $6, $7, $8}')
          local file=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=""; print $0}' | sed 's/^ *//')
          formatted_results+="$size | $date | $file\n"
        done <<< "$results"
        
        dialog_info "Large Files" "Found $file_count files larger than $min_size in $search_path.\nShowing the first $display_count files:\n\nSIZE | DATE | FILENAME\n------------------------------------\n$formatted_results"
      fi
      
      # Clean up
      rm -f "$temp_file"
      
      log "Large file search completed"
      ;;
    old)
      # Find old files
      local days=$(dialog_input "Days" "Enter the minimum age in days:" "365")
      
      if [ -z "$days" ]; then
        log "Days input cancelled"
        return
      fi
      
      # Validate days input
      if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        dialog_info "Invalid Input" "Please enter a valid number of days."
        log "Invalid days input: $days"
        return
      fi
      
      local search_path=$(dialog_input "Search Path" "Enter the path to search in:" "/home")
      
      if [ -z "$search_path" ]; then
        log "Search path input cancelled"
        return
      fi
      
      if [ ! -d "$search_path" ]; then
        dialog_info "Invalid Path" "The specified path does not exist or is not a directory."
        log "Invalid path: $search_path"
        return
      fi
      
      # Create a temporary file for results
      local temp_file=$(mktemp)
      
      # Show progress
      (
        echo "0"; echo "XXX"; echo "Preparing to search for old files..."; echo "XXX"
        
        echo "10"; echo "XXX"; echo "Searching for files older than $days days in $search_path..."; echo "XXX"
        find "$search_path" -type f -mtime +$days -exec ls -lh {} \; > "$temp_file" 2>/dev/null
        
        echo "90"; echo "XXX"; echo "Sorting results..."; echo "XXX"
        sort -k 6,8 "$temp_file" > "${temp_file}.sorted"
        mv "${temp_file}.sorted" "$temp_file"
        
        echo "100"; echo "XXX"; echo "Search completed."; echo "XXX"
        
      ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Finding Old Files" --gauge "Please wait..." 10 70 0
      
      # Display results
      local file_count=$(wc -l < "$temp_file")
      local results=$(head -n 100 "$temp_file")
      
      if [ "$file_count" -eq 0 ]; then
        dialog_info "No Files Found" "No files older than $days days found in $search_path."
      else
        local display_count=100
        if [ "$file_count" -lt 100 ]; then
          display_count="$file_count"
        fi
        
        # Create a more readable format
        local formatted_results=""
        while IFS= read -r line; do
          local perms=$(echo "$line" | awk '{print $1}')
          local size=$(echo "$line" | awk '{print $5}')
          local date=$(echo "$line" | awk '{print $6, $7, $8}')
          local file=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=""; print $0}' | sed 's/^ *//')
          formatted_results+="$date | $size | $file\n"
        done <<< "$results"
        
        dialog_info "Old Files" "Found $file_count files older than $days days in $search_path.\nShowing the first $display_count files:\n\nDATE | SIZE | FILENAME\n------------------------------------\n$formatted_results"
      fi
      
      # Clean up
      rm -f "$temp_file"
      
      log "Old file search completed"
      ;;
  esac
}

# Function for disk management main menu
disk_management() {
  log "Disk management started"
  
  while true; do
    local action=$(dialog_menu "Disk Management" "Choose an option:" \
      "info" "Disk information" \
      "partition" "Partition disk" \
      "format" "Format partition" \
      "mount" "Mount partition" \
      "unmount" "Unmount partition" \
      "health" "Check disk health" \
      "usage" "Analyze disk usage" \
      "backup" "Backup disk or partition" \
      "back" "Back to main menu")
    
    case $action in
      info)
        disk_info
        ;;
      partition)
        partition_disk
        ;;
      format)
        format_partition
        ;;
      mount)
        mount_partition
        ;;
      unmount)
        unmount_partition
        ;;
      health)
        check_disk_health
        ;;
      usage)
        analyze_disk_usage
        ;;
      backup)
        backup_disk
        ;;
      back|"")
        log "Disk management exited"
        return
        ;;
    esac
  done
}

# Function for backing up disks or partitions
backup_disk() {
  log "Disk backup started"
  
  # Check if dd is available
  if ! command -v dd &> /dev/null; then
    dialog_info "Tool Missing" "The dd tool is required for disk backup but could not be found."
    log "dd tool not found"
    return
  fi
  
  # Choose what to backup
  local backup_type=$(dialog_menu "Backup Type" "Choose what to backup:" \
    "disk" "Entire disk" \
    "partition" "Single partition" \
    "back" "Cancel")
  
  if [ -z "$backup_type" ] || [ "$backup_type" = "back" ]; then
    log "Backup type selection cancelled"
    return
  fi
  
  # Source selection
  local source=""
  local source_options=()
  
  if [ "$backup_type" = "disk" ]; then
    # List physical disks
    local disks=$(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr")
    
    while read -r line; do
      local name=$(echo "$line" | awk '{print $1}')
      local size=$(echo "$line" | awk '{print $2}')
      local model=$(echo "$line" | awk '{$1=""; $2=""; print $0}' | sed 's/^ *//')
      source_options+=("/dev/$name" "$size - $model")
    done <<< "$disks"
    
    source=$(dialog_menu "Select Disk" "Choose a disk to backup:" "${source_options[@]}")
  else
    # List partitions
    local partitions=$(lsblk -n -o NAME,SIZE,TYPE,MOUNTPOINT | grep "part")
    
    while read -r line; do
      local name=$(echo "$line" | awk '{print $1}')
      local size=$(echo "$line" | awk '{print $2}')
      local mountpoint=$(echo "$line" | awk '{print $4}')
      
      if [ -z "$mountpoint" ]; then
        mountpoint="Not mounted"
      fi
      
      source_options+=("/dev/$name" "$size - $mountpoint")
    done <<< "$partitions"
    
    source=$(dialog_menu "Select Partition" "Choose a partition to backup:" "${source_options[@]}")
  fi
  
  if [ -z "$source" ]; then
    log "Backup source selection cancelled"
    return
  fi
  
  # Destination file
  local default_name=$(basename "$source")
  local timestamp=$(date +%Y%m%d%H%M%S)
  local default_path="$HOME/${default_name}_backup_$timestamp.img"
  
  local destination=$(dialog_input "Backup Destination" "Enter the path for the backup file:" "$default_path")
  
  if [ -z "$destination" ]; then
    log "Backup destination input cancelled"
    return
  fi
  
  # Create the destination directory if it doesn't exist
  local dest_dir=$(dirname "$destination")
  mkdir -p "$dest_dir"
  
  # Confirm backup
  if ! dialog_confirm "Confirm Backup" "You are about to backup:\nSource: $source\nDestination: $destination\n\nThis may take a long time depending on the size. Continue?"; then
    log "Backup operation cancelled"
    return
  fi
  
  # Perform the backup
  (
    echo "0"; echo "XXX"; echo "Preparing backup..."; echo "XXX"
    
    # Get disk size in bytes
    local size_bytes=$(blockdev --getsize64 "$source" 2>/dev/null)
    local bs="4M"
    
    echo "5"; echo "XXX"; echo "Starting backup of $source..."; echo "XXX"
    
    # Start dd with status reporting
    (
      dd if="$source" of="$destination" bs=$bs status=progress
    ) 2>&1 | 
    # Parse dd output to update the progress bar
    while IFS= read -r line; do
      if [[ "$line" =~ ([0-9]+)\ bytes\ \(([0-9.]+)\ ([kMGT]?B)\)\ copied,\ ([0-9.]+)\ s,\ ([0-9.]+)\ ([kMGT]?B)/s ]]; then
        local copied=${BASH_REMATCH[1]}
        local speed=${BASH_REMATCH[5]}
        local speed_unit=${BASH_REMATCH[6]}
        
        if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 0 ]; then
          local percent=$((copied * 100 / size_bytes))
          
          # Keep percentage in the 5-95 range to show progress
          if [ $percent -lt 5 ]; then
            percent=5
          elif [ $percent -gt 95 ]; then
            percent=95
          fi
          
          echo "$percent"; echo "XXX"; echo "Backing up $source...\n$percent% complete\nSpeed: $speed $speed_unit/s"; echo "XXX"
        fi
      fi
    done
    
    echo "98"; echo "XXX"; echo "Finalizing backup..."; echo "XXX"
    sync
    
    echo "100"; echo "XXX"; echo "Backup completed."; echo "XXX"
    
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Disk Backup" --gauge "Please wait..." 10 70 0
  
  # Check if backup was successful
  if [ -f "$destination" ]; then
    local file_size=$(du -h "$destination" | awk '{print $1}')
    log "Backup of $source to $destination completed successfully (size: $file_size)"
    dialog_info "Backup Complete" "Backup of $source has been completed successfully.\n\nBackup file: $destination\nSize: $file_size"
  else
    log "Backup of $source to $destination failed"
    dialog_info "Backup Failed" "Failed to create backup of $source.\n\nPlease check available disk space and permissions."
  fi
}

#######################################
# PERFORMANCE MANAGEMENT FUNCTIONS
#######################################

# Function for checking system resources
check_resources() {
  log "System resources check started"
  
  # Temporary files for data collection
  local cpu_temp=$(mktemp)
  local memory_temp=$(mktemp)
  local disk_temp=$(mktemp)
  local network_temp=$(mktemp)
  
  # Collect data
  (
    echo "10"; echo "XXX"; echo "Collecting CPU information..."; echo "XXX"
    
    # CPU info
    echo "CPU INFORMATION" > "$cpu_temp"
    echo "================" >> "$cpu_temp"
    echo "" >> "$cpu_temp"
    
    echo "Model:" >> "$cpu_temp"
    lscpu | grep "Model name" | sed 's/Model name: *//g' >> "$cpu_temp"
    echo "" >> "$cpu_temp"
    
    echo "CPU Cores:" >> "$cpu_temp"
    nproc --all >> "$cpu_temp"
    echo "" >> "$cpu_temp"
    
    echo "CPU Usage:" >> "$cpu_temp"
    top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1"%"}' >> "$cpu_temp"
    echo "" >> "$cpu_temp"
    
    echo "Load Average (1m, 5m, 15m):" >> "$cpu_temp"
    uptime | sed 's/.*load average: //' >> "$cpu_temp"
    echo "" >> "$cpu_temp"
    
    echo "Top CPU Processes:" >> "$cpu_temp"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6 >> "$cpu_temp"
    
    echo "30"; echo "XXX"; echo "Collecting memory information..."; echo "XXX"
    
    # Memory info
    echo "MEMORY INFORMATION" > "$memory_temp"
    echo "==================" >> "$memory_temp"
    echo "" >> "$memory_temp"
    
    echo "Memory Summary:" >> "$memory_temp"
    free -h >> "$memory_temp"
    echo "" >> "$memory_temp"
    
    echo "Swap Usage:" >> "$memory_temp"
    swapon --show 2>/dev/null >> "$memory_temp" || echo "No swap enabled" >> "$memory_temp"
    echo "" >> "$memory_temp"
    
    echo "Top Memory Processes:" >> "$memory_temp"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6 >> "$memory_temp"
    
    echo "50"; echo "XXX"; echo "Collecting disk information..."; echo "XXX"
    
    # Disk info
    echo "DISK INFORMATION" > "$disk_temp"
    echo "================" >> "$disk_temp"
    echo "" >> "$disk_temp"
    
    echo "Disk Usage:" >> "$disk_temp"
    df -h >> "$disk_temp"
    echo "" >> "$disk_temp"
    
    echo "Disk I/O:" >> "$disk_temp"
    iostat -x 2>/dev/null >> "$disk_temp" || echo "iostat not available (install sysstat package)" >> "$disk_temp"
    
    echo "70"; echo "XXX"; echo "Collecting network information..."; echo "XXX"
    
    # Network info
    echo "NETWORK INFORMATION" > "$network_temp"
    echo "===================" >> "$network_temp"
    echo "" >> "$network_temp"
    
    echo "Network Interfaces:" >> "$network_temp"
    ip -o link show | awk -F': ' '{print $2}' | while read -r interface; do
      echo "Interface: $interface" >> "$network_temp"
      ip -s link show "$interface" | grep -A 2 "RX:" >> "$network_temp"
      ip -s link show "$interface" | grep -A 2 "TX:" >> "$network_temp"
      echo "" >> "$network_temp"
    done
    
    echo "Network Connections:" >> "$network_temp"
    ss -tuln | head -n 20 >> "$network_temp"
    
    echo "90"; echo "XXX"; echo "Finalizing system resource report..."; echo "XXX"
    
    # Combine all data
    (
      cat "$cpu_temp"
      echo ""
      echo "======================================================"
      echo ""
      cat "$memory_temp"
      echo ""
      echo "======================================================"
      echo ""
      cat "$disk_temp"
      echo ""
      echo "======================================================"
      echo ""
      cat "$network_temp"
    ) > /tmp/system_resources.txt
    
    # Clean up temp files
    rm -f "$cpu_temp" "$memory_temp" "$disk_temp" "$network_temp"
    
    echo "100"; echo "XXX"; echo "System resource check completed."; echo "XXX"
    
  ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Checking System Resources" --gauge "Please wait..." 10 70 0
  
  # Create a backup
  mkdir -p "$BACKUP_DIR/system_state"
  cp /tmp/system_resources.txt "$BACKUP_DIR/system_state/resources_$(date +%Y%m%d%H%M%S).txt"
  
  # Display resource summary
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1"%"}')
  local mem_info=$(free -h | grep Mem)
  local mem_total=$(echo "$mem_info" | awk '{print $2}')
  local mem_used=$(echo "$mem_info" | awk '{print $3}')
  local mem_free=$(echo "$mem_info" | awk '{print $4}')
  local mem_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
  
  local disk_usage=$(df -h --output=pcent / | tail -n 1)
  local load_avg=$(uptime | awk -F'load average: ' '{print $2}')
  
  local summary="SYSTEM RESOURCES SUMMARY\n\n"
  summary+="CPU Usage: $cpu_usage\n"
  summary+="Memory: $mem_used used / $mem_total total ($mem_usage%)\n"
  summary+="Disk Usage: $disk_usage (root filesystem)\n"
  summary+="Load Average: $load_avg\n\n"
  
  summary+="Top CPU Process:\n"
  summary+=$(ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 2 | tail -n 1)
  summary+="\n\n"
  
  summary+="Top Memory Process:\n"
  summary+=$(ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -n 2 | tail -n 1)
  summary+="\n\n"
  
  summary+="A detailed system resource report has been saved to:\n"
  summary+="/tmp/system_resources.txt\n"
  summary+="and backed up to $BACKUP_DIR/system_state/"
  
  dialog_info "System Resources" "$summary"
  
  # Ask if user wants to view the full report
  if dialog_confirm "Full Report" "Do you want to view the full system resource report?"; then
    # Display full report
    dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "System Resource Report" --textbox "/tmp/system_resources.txt" 24 80
  fi
}

# Function for system tuning
tune_system() {
  log "System tuning started"
  
  # Show tuning options
  local tuning_option=$(dialog_menu "System Tuning" "Choose a tuning option:" \
    "swappiness" "Adjust swappiness (memory management)" \
    "io" "Configure I/O scheduler" \
    "network" "Tune network parameters" \
    "cpu" "CPU governor settings" \
    "filesystem" "Filesystem optimizations" \
    "services" "Disable unnecessary services" \
    "boot" "Optimize boot process" \
    "back" "Back to performance menu")
  
  if [ -z "$tuning_option" ] || [ "$tuning_option" = "back" ]; then
    log "Tuning option selection cancelled"
    return
  fi
  
  # Handle each tuning option
  case $tuning_option in
    swappiness)
      # Configure swappiness
      local current_swappiness=$(cat /proc/sys/vm/swappiness)
      
      local new_swappiness=$(dialog_radiolist "Swappiness" "Current swappiness value: $current_swappiness\n\nSelect a new value (lower values reduce swap usage):" \
        "10" "Low (Desktop/Development/SSD)" $([ "$current_swappiness" -eq 10 ] && echo "on" || echo "off") \
        "30" "Medium-Low (General Purpose)" $([ "$current_swappiness" -eq 30 ] && echo "on" || echo "off") \
        "60" "Medium (Default)" $([ "$current_swappiness" -eq 60 ] && echo "on" || echo "off") \
        "80" "Medium-High (Database Server)" $([ "$current_swappiness" -eq 80 ] && echo "on" || echo "off") \
        "100" "High (High Memory Applications)" $([ "$current_swappiness" -eq 100 ] && echo "on" || echo "off") \
        "custom" "Custom value" "off")
      
      if [ -z "$new_swappiness" ]; then
        log "Swappiness configuration cancelled"
        return
      fi
      
      if [ "$new_swappiness" = "custom" ]; then
        new_swappiness=$(dialog_input "Custom Swappiness" "Enter a custom swappiness value (0-100):" "$current_swappiness")
        
        if [ -z "$new_swappiness" ]; then
          log "Custom swappiness input cancelled"
          return
        fi
        
        # Validate input
        if ! [[ "$new_swappiness" =~ ^[0-9]+$ ]] || [ "$new_swappiness" -lt 0 ] || [ "$new_swappiness" -gt 100 ]; then
          dialog_info "Invalid Value" "Swappiness value must be between 0 and 100."
          log "Invalid swappiness value: $new_swappiness"
          return
        fi
      fi
      
      # Set new swappiness
      if [ "$new_swappiness" != "$current_swappiness" ]; then
        # Set current value
        sysctl -w vm.swappiness=$new_swappiness
        
        # Make permanent
        if grep -q "vm.swappiness" /etc/sysctl.conf; then
          sed -i "s/vm.swappiness=.*/vm.swappiness=$new_swappiness/" /etc/sysctl.conf
        else
          echo "vm.swappiness=$new_swappiness" >> /etc/sysctl.conf
        fi
        
        log "Swappiness changed from $current_swappiness to $new_swappiness"
        
        local impact=""
        if [ "$new_swappiness" -lt "$current_swappiness" ]; then
          impact="This will reduce swap usage and potentially improve responsiveness, but may increase memory pressure."
        else
          impact="This will increase swap usage, potentially freeing up memory for applications but may reduce responsiveness."
        fi
        
        dialog_info "Swappiness Changed" "Swappiness has been changed from $current_swappiness to $new_swappiness.\n\n$impact\n\nThe change has been applied immediately and will persist after reboot."
      else
        dialog_info "No Change" "Swappiness value is already set to $current_swappiness. No changes made."
        log "Swappiness unchanged from $current_swappiness"
      fi
      ;;
    io)
      # Configure I/O scheduler
      
      # Get list of block devices
      local block_devices=$(lsblk -d -n -o NAME | grep -v "loop" | grep -v "sr")
      
      if [ -z "$block_devices" ]; then
        dialog_info "No Block Devices" "No block devices found."
        log "No block devices found"
        return
      fi
      
      # Choose device
      local device_options=()
      while read -r device; do
        device_options+=("$device" "Block device")
      done <<< "$block_devices"
      
      local selected_device=$(dialog_menu "Select Device" "Choose a block device to configure:" "${device_options[@]}")
      
      if [ -z "$selected_device" ]; then
        log "Device selection cancelled"
        return
      fi
      
      # Check if I/O scheduler settings are available
      if [ ! -f "/sys/block/$selected_device/queue/scheduler" ]; then
        dialog_info "Not Supported" "I/O scheduler configuration is not supported for this device."
        log "I/O scheduler not supported for $selected_device"
        return
      fi
      
      # Get current scheduler
      local schedulers=$(cat "/sys/block/$selected_device/queue/scheduler")
      local current_scheduler=$(echo "$schedulers" | grep -o '\[.*\]' | tr -d '[]')
      
      # Extract available schedulers
      local available_schedulers=$(echo "$schedulers" | tr -d '[]' | tr ' ' '\n')
      
      # Build scheduler options
      local scheduler_options=()
      while read -r scheduler; do
        if [ "$scheduler" = "$current_scheduler" ]; then
          scheduler_options+=("$scheduler" "I/O Scheduler" "on")
        else
          scheduler_options+=("$scheduler" "I/O Scheduler" "off")
        fi
      done <<< "$available_schedulers"
      
      # Choose new scheduler
      local new_scheduler=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
        --title "I/O Scheduler" \
        --radiolist "Current scheduler for /dev/$selected_device: $current_scheduler\n\nSelect a new scheduler:" 15 60 10 \
        "${scheduler_options[@]}" 3>&1 1>&2 2>&3)
      
      if [ -z "$new_scheduler" ]; then
        log "Scheduler selection cancelled"
        return
      fi
      
      # Recommended description
      local scheduler_desc=""
      case $new_scheduler in
        noop)
          scheduler_desc="Simple FIFO queue, minimal overhead (good for SSDs)"
          ;;
        deadline)
          scheduler_desc="Prioritizes read operations (good for database servers)"
          ;;
        cfq)
          scheduler_desc="Fair queuing for balanced I/O (good for general use)"
          ;;
        bfq)
          scheduler_desc="Budget Fair Queuing for desktop responsiveness"
          ;;
        mq-deadline)
          scheduler_desc="Multi-queue deadline scheduler (modern version of deadline)"
          ;;
        kyber)
          scheduler_desc="Latency-oriented scheduler for fast devices"
          ;;
        *)
          scheduler_desc="Custom scheduler"
          ;;
      esac
      
      # Set new scheduler
      if [ "$new_scheduler" != "$current_scheduler" ]; then
        # Set current value
        echo "$new_scheduler" > "/sys/block/$selected_device/queue/scheduler"
        
        # Make permanent
        local udev_rule="/etc/udev/rules.d/60-scheduler.rules"
        
        # Create or update udev rule
        if [ -f "$udev_rule" ]; then
          if grep -q "KERNEL==\"$selected_device\"" "$udev_rule"; then
            sed -i "/KERNEL==\"$selected_device\"/c\ACTION==\"add|change\", KERNEL==\"$selected_device\", ATTR{queue/scheduler}=\"$new_scheduler\"" "$udev_rule"
          else
            echo "ACTION==\"add|change\", KERNEL==\"$selected_device\", ATTR{queue/scheduler}=\"$new_scheduler\"" >> "$udev_rule"
          fi
        else
          echo "# Set I/O schedulers for devices" > "$udev_rule"
          echo "ACTION==\"add|change\", KERNEL==\"$selected_device\", ATTR{queue/scheduler}=\"$new_scheduler\"" >> "$udev_rule"
        fi
        
        log "I/O scheduler for $selected_device changed from $current_scheduler to $new_scheduler"
        
        dialog_info "Scheduler Changed" "I/O scheduler for /dev/$selected_device has been changed from $current_scheduler to $new_scheduler.\n\nDescription: $scheduler_desc\n\nThe change has been applied immediately and will persist after reboot."
      else
        dialog_info "No Change" "I/O scheduler is already set to $current_scheduler. No changes made."
        log "I/O scheduler unchanged from $current_scheduler"
      fi
      ;;
    network)
      # Tune network parameters
      local network_option=$(dialog_menu "Network Tuning" "Choose a network tuning option:" \
        "tcp" "TCP performance parameters" \
        "buffers" "Network buffer sizes" \
        "congestion" "TCP congestion algorithm" \
        "dns" "DNS resolver settings" \
        "back" "Back to tuning menu")
      
      if [ -z "$network_option" ] || [ "$network_option" = "back" ]; then
        log "Network tuning option selection cancelled"
        return
      fi
      
      case $network_option in
        tcp)
          # TCP performance parameters
          local tcp_params=$(dialog_menu "TCP Parameters" "Choose a TCP parameter to tune:" \
            "tcp_fastopen" "TCP Fast Open (faster connections)" \
            "tcp_slow_start_after_idle" "Slow Start After Idle (bandwidth recovery)" \
            "tcp_sack" "Selective Acknowledgments (improved recovery)" \
            "tcp_timestamps" "TCP Timestamps (better RTT estimation)" \
            "back" "Back to network tuning")
          
          if [ -z "$tcp_params" ] || [ "$tcp_params" = "back" ]; then
            log "TCP parameter selection cancelled"
            return
          fi
          
          # Get current value
          local current_value=$(sysctl -n net.ipv4.$tcp_params)
          
          # Choose new value
          local new_value=""
          
          case $tcp_params in
            tcp_fastopen)
              new_value=$(dialog_radiolist "TCP Fast Open" "Current value: $current_value\n\nSelect a new value:" \
                "0" "Disabled" $([ "$current_value" -eq 0 ] && echo "on" || echo "off") \
                "1" "Outgoing connections only" $([ "$current_value" -eq 1 ] && echo "on" || echo "off") \
                "2" "Incoming connections only" $([ "$current_value" -eq 2 ] && echo "on" || echo "off") \
                "3" "Both incoming and outgoing (recommended)" $([ "$current_value" -eq 3 ] && echo "on" || echo "off"))
              ;;
            tcp_slow_start_after_idle)
              new_value=$(dialog_radiolist "TCP Slow Start After Idle" "Current value: $current_value\n\nSelect a new value:" \
                "0" "Disabled (better for stable connections)" $([ "$current_value" -eq 0 ] && echo "on" || echo "off") \
                "1" "Enabled (default)" $([ "$current_value" -eq 1 ] && echo "on" || echo "off"))
              ;;
            tcp_sack|tcp_timestamps)
              new_value=$(dialog_radiolist "TCP $tcp_params" "Current value: $current_value\n\nSelect a new value:" \
                "0" "Disabled" $([ "$current_value" -eq 0 ] && echo "on" || echo "off") \
                "1" "Enabled (recommended)" $([ "$current_value" -eq 1 ] && echo "on" || echo "off"))
              ;;
          esac
          
          if [ -z "$new_value" ]; then
            log "TCP parameter value selection cancelled"
            return
          fi
          
          # Set new value
          if [ "$new_value" != "$current_value" ]; then
            # Set current value
            sysctl -w net.ipv4.$tcp_params=$new_value
            
            # Make permanent
            if grep -q "net.ipv4.$tcp_params" /etc/sysctl.conf; then
              sed -i "s/net.ipv4.$tcp_params=.*/net.ipv4.$tcp_params=$new_value/" /etc/sysctl.conf
            else
              echo "net.ipv4.$tcp_params=$new_value" >> /etc/sysctl.conf
            fi
            
            log "TCP parameter $tcp_params changed from $current_value to $new_value"
            dialog_info "Parameter Changed" "TCP parameter $tcp_params has been changed from $current_value to $new_value.\n\nThe change has been applied immediately and will persist after reboot."
          else
            dialog_info "No Change" "TCP parameter $tcp_params is already set to $current_value. No changes made."
            log "TCP parameter $tcp_params unchanged from $current_value"
          fi
          ;;
        buffers)
          # Network buffer sizes
          local buffer_params=$(dialog_menu "Network Buffers" "Choose a buffer parameter to tune:" \
            "rmem" "Socket receive buffers" \
            "wmem" "Socket send buffers" \
            "max_backlog" "Maximum connection backlog" \
            "back" "Back to network tuning")
          
          if [ -z "$buffer_params" ] || [ "$buffer_params" = "back" ]; then
            log "Buffer parameter selection cancelled"
            return
          fi
          
          case $buffer_params in
            rmem|wmem)
              # Get current values
              local min_val=$(sysctl -n net.ipv4.tcp_${buffer_params}_min)
              local default_val=$(sysctl -n net.ipv4.tcp_${buffer_params}_default)
              local max_val=$(sysctl -n net.ipv4.tcp_${buffer_params}_max)
              
              # Show current values
              dialog_info "Current Values" "Current $buffer_params buffer sizes:\n\nMinimum: $min_val bytes\nDefault: $default_val bytes\nMaximum: $max_val bytes"
              
              # Get profile
              local profile=$(dialog_menu "Buffer Profile" "Choose a $buffer_params buffer profile:" \
                "default" "Default values" \
                "server" "Server optimized (high bandwidth)" \
                "desktop" "Desktop optimized" \
                "custom" "Custom values" \
                "back" "Cancel")
              
              if [ -z "$profile" ] || [ "$profile" = "back" ]; then
                log "Buffer profile selection cancelled"
                return
              fi
              
              # Set values based on profile
              local new_min=0
              local new_default=0
              local new_max=0
              
              case $profile in
                default)
                  new_min=4096
                  new_default=87380
                  new_max=4194304
                  ;;
                server)
                  new_min=8192
                  new_default=131072
                  new_max=16777216
                  ;;
                desktop)
                  new_min=4096
                  new_default=65536
                  new_max=8388608
                  ;;
                custom)
                  new_min=$(dialog_input "Minimum Buffer" "Enter the minimum $buffer_params buffer size (bytes):" "$min_val")
                  if [ -z "$new_min" ]; then return; fi
                  
                  new_default=$(dialog_input "Default Buffer" "Enter the default $buffer_params buffer size (bytes):" "$default_val")
                  if [ -z "$new_default" ]; then return; fi
                  
                  new_max=$(dialog_input "Maximum Buffer" "Enter the maximum $buffer_params buffer size (bytes):" "$max_val")
                  if [ -z "$new_max" ]; then return; fi
                  ;;
              esac
              
              # Validate values
              if [ "$new_min" -gt "$new_default" ] || [ "$new_default" -gt "$new_max" ]; then
                dialog_info "Invalid Values" "Buffer sizes must follow: min ≤ default ≤ max"
                log "Invalid buffer values: min=$new_min, default=$new_default, max=$new_max"
                return
              fi
              
              # Set new values
              sysctl -w net.ipv4.tcp_${buffer_params}_min=$new_min
              sysctl -w net.ipv4.tcp_${buffer_params}_default=$new_default
              sysctl -w net.ipv4.tcp_${buffer_params}_max=$new_max
              
              # Make permanent
              if grep -q "net.ipv4.tcp_${buffer_params}_min" /etc/sysctl.conf; then
                sed -i "s/net.ipv4.tcp_${buffer_params}_min=.*/net.ipv4.tcp_${buffer_params}_min=$new_min/" /etc/sysctl.conf
              else
                echo "net.ipv4.tcp_${buffer_params}_min=$new_min" >> /etc/sysctl.conf
              fi
              
              if grep -q "net.ipv4.tcp_${buffer_params}_default" /etc/sysctl.conf; then
                sed -i "s/net.ipv4.tcp_${buffer_params}_default=.*/net.ipv4.tcp_${buffer_params}_default=$new_default/" /etc/sysctl.conf
              else
                echo "net.ipv4.tcp_${buffer_params}_default=$new_default" >> /etc/sysctl.conf
              fi
              
              if grep -q "net.ipv4.tcp_${buffer_params}_max" /etc/sysctl.conf; then
                sed -i "s/net.ipv4.tcp_${buffer_params}_max=.*/net.ipv4.tcp_${buffer_params}_max=$new_max/" /etc/sysctl.conf
              else
                echo "net.ipv4.tcp_${buffer_params}_max=$new_max" >> /etc/sysctl.conf
              fi
              
              log "TCP ${buffer_params} buffers changed to min=$new_min, default=$new_default, max=$new_max"
              dialog_info "Buffers Changed" "TCP ${buffer_params} buffers have been changed to:\n\nMinimum: $new_min bytes\nDefault: $new_default bytes\nMaximum: $new_max bytes\n\nThe change has been applied immediately and will persist after reboot."
              ;;
            max_backlog)
              # Get current value
              local current_backlog=$(sysctl -n net.core.netdev_max_backlog)
              
              # Choose new value
              local new_backlog=$(dialog_radiolist "Max Backlog" "Current value: $current_backlog\n\nSelect a new value:" \
                "1000" "Default" $([ "$current_backlog" -eq 1000 ] && echo "on" || echo "off") \
                "2500" "Medium (General server)" $([ "$current_backlog" -eq 2500 ] && echo "on" || echo "off") \
                "5000" "High (Busy server)" $([ "$current_backlog" -eq 5000 ] && echo "on" || echo "off") \
                "10000" "Very high (Heavy load server)" $([ "$current_backlog" -eq 10000 ] && echo "on" || echo "off") \
                "custom" "Custom value" "off")
              
              if [ -z "$new_backlog" ]; then
                log "Backlog selection cancelled"
                return
              fi
              
              if [ "$new_backlog" = "custom" ]; then
                new_backlog=$(dialog_input "Custom Backlog" "Enter a custom backlog value:" "$current_backlog")
                
                if [ -z "$new_backlog" ]; then
                  log "Custom backlog input cancelled"
                  return
                fi
                
                # Validate input
                if ! [[ "$new_backlog" =~ ^[0-9]+$ ]] || [ "$new_backlog" -lt 100 ]; then
                  dialog_info "Invalid Value" "Backlog must be a number greater than 100."
                  log "Invalid backlog value: $new_backlog"
                  return
                fi
              fi
              
              # Set new value
              if [ "$new_backlog" != "$current_backlog" ]; then
                # Set current value
                sysctl -w net.core.netdev_max_backlog=$new_backlog
                
                # Make permanent
                if grep -q "net.core.netdev_max_backlog" /etc/sysctl.conf; then
                  sed -i "s/net.core.netdev_max_backlog=.*/net.core.netdev_max_backlog=$new_backlog/" /etc/sysctl.conf
                else
                  echo "net.core.netdev_max_backlog=$new_backlog" >> /etc/sysctl.conf
                fi
                
                log "Network max backlog changed from $current_backlog to $new_backlog"
                dialog_info "Backlog Changed" "Maximum network connection backlog has been changed from $current_backlog to $new_backlog.\n\nThe change has been applied immediately and will persist after reboot."
              else
                dialog_info "No Change" "Maximum network connection backlog is already set to $current_backlog. No changes made."
                log "Network max backlog unchanged from $current_backlog"
              fi
              ;;
          esac
          ;;
        congestion)
          # TCP congestion algorithm
          
          # Get available congestion algorithms
          if [ ! -f "/proc/sys/net/ipv4/tcp_available_congestion_control" ]; then
            dialog_info "Not Supported" "TCP congestion algorithm configuration is not supported on this system."
            log "TCP congestion control not supported"
            return
          fi
          
          local available_algorithms=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)
          local current_algorithm=$(cat /proc/sys/net/ipv4/tcp_congestion_control)
          
          # Build algorithm options
          local algorithm_options=()
          for algorithm in $available_algorithms; do
            if [ "$algorithm" = "$current_algorithm" ]; then
              algorithm_options+=("$algorithm" "Congestion Algorithm" "on")
            else
              algorithm_options+=("$algorithm" "Congestion Algorithm" "off")
            fi
          done
          
          # Choose new algorithm
          local new_algorithm=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
            --title "TCP Congestion Algorithm" \
            --radiolist "Current algorithm: $current_algorithm\n\nSelect a new algorithm:" 15 70 10 \
            "${algorithm_options[@]}" 3>&1 1>&2 2>&3)
          
          if [ -z "$new_algorithm" ]; then
            log "Algorithm selection cancelled"
            return
          fi
          
          # Algorithm descriptions
          local algorithm_desc=""
          case $new_algorithm in
            cubic)
              algorithm_desc="Default algorithm, good for most connections"
              ;;
            reno)
              algorithm_desc="Basic algorithm, standard implementation"
              ;;
            bbr)
              algorithm_desc="Google's BBR algorithm, excellent for high bandwidth connections"
              ;;
            htcp)
              algorithm_desc="H-TCP algorithm, good for high-speed, long-distance networks"
              ;;
            vegas)
              algorithm_desc="Vegas algorithm, focuses on reducing latency"
              ;;
            westwood)
              algorithm_desc="Westwood+ algorithm, good for wireless connections"
              ;;
            *)
              algorithm_desc="Custom algorithm"
              ;;
          esac
          
          # Set new algorithm
          if [ "$new_algorithm" != "$current_algorithm" ]; then
            # Set current value
            sysctl -w net.ipv4.tcp_congestion_control=$new_algorithm
            
            # Make permanent
            if grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
              sed -i "s/net.ipv4.tcp_congestion_control=.*/net.ipv4.tcp_congestion_control=$new_algorithm/" /etc/sysctl.conf
            else
              echo "net.ipv4.tcp_congestion_control=$new_algorithm" >> /etc/sysctl.conf
            fi
            
            log "TCP congestion algorithm changed from $current_algorithm to $new_algorithm"
            dialog_info "Algorithm Changed" "TCP congestion algorithm has been changed from $current_algorithm to $new_algorithm.\n\nDescription: $algorithm_desc\n\nThe change has been applied immediately and will persist after reboot."
          else
            dialog_info "No Change" "TCP congestion algorithm is already set to $current_algorithm. No changes made."
            log "TCP congestion algorithm unchanged from $current_algorithm"
          fi
          ;;
        dns)
          # DNS resolver settings
          
          # Get current values
          local current_timeout=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo "N/A")
          local current_retries=$(sysctl -n net.ipv4.tcp_retries2 2>/dev/null || echo "N/A")
          
          # Choose what to configure
          local dns_option=$(dialog_menu "DNS Settings" "Choose a DNS setting to configure:" \
            "timeout" "Connection timeout (current: $current_timeout)" \
            "retries" "Number of retries (current: $current_retries)" \
            "resolver" "DNS resolver configuration" \
            "back" "Back to network tuning")
          
          if [ -z "$dns_option" ] || [ "$dns_option" = "back" ]; then
            log "DNS option selection cancelled"
            return
          fi
          
          case $dns_option in
            timeout)
              # Connection timeout
              local new_timeout=$(dialog_radiolist "Connection Timeout" "Current value: $current_timeout seconds\n\nSelect a new value:" \
                "15" "Fast timeout (high traffic servers)" $([ "$current_timeout" -eq 15 ] && echo "on" || echo "off") \
                "30" "Medium timeout (general servers)" $([ "$current_timeout" -eq 30 ] && echo "on" || echo "off") \
                "60" "Default timeout" $([ "$current_timeout" -eq 60 ] && echo "on" || echo "off") \
                "120" "Long timeout (stable connections)" $([ "$current_timeout" -eq 120 ] && echo "on" || echo "off") \
                "custom" "Custom value" "off")
              
              if [ -z "$new_timeout" ]; then
                log "Timeout selection cancelled"
                return
              fi
              
              if [ "$new_timeout" = "custom" ]; then
                new_timeout=$(dialog_input "Custom Timeout" "Enter a custom timeout value (seconds):" "$current_timeout")
                
                if [ -z "$new_timeout" ]; then
                  log "Custom timeout input cancelled"
                  return
                fi
                
                # Validate input
                if ! [[ "$new_timeout" =~ ^[0-9]+$ ]] || [ "$new_timeout" -lt 5 ]; then
                  dialog_info "Invalid Value" "Timeout must be a number greater than 5."
                  log "Invalid timeout value: $new_timeout"
                  return
                fi
              fi
              
              # Set new value
              if [ "$new_timeout" != "$current_timeout" ]; then
                # Set current value
                sysctl -w net.ipv4.tcp_fin_timeout=$new_timeout
                
                # Make permanent
                if grep -q "net.ipv4.tcp_fin_timeout" /etc/sysctl.conf; then
                  sed -i "s/net.ipv4.tcp_fin_timeout=.*/net.ipv4.tcp_fin_timeout=$new_timeout/" /etc/sysctl.conf
                else
                  echo "net.ipv4.tcp_fin_timeout=$new_timeout" >> /etc/sysctl.conf
                fi
                
                log "TCP FIN timeout changed from $current_timeout to $new_timeout"
                dialog_info "Timeout Changed" "TCP FIN timeout has been changed from $current_timeout to $new_timeout seconds.\n\nThe change has been applied immediately and will persist after reboot."
              else
                dialog_info "No Change" "TCP FIN timeout is already set to $current_timeout. No changes made."
                log "TCP FIN timeout unchanged from $current_timeout"
              fi
              ;;
            retries)
              # Number of retries
              local new_retries=$(dialog_radiolist "Connection Retries" "Current value: $current_retries\n\nSelect a new value:" \
                "5" "Low retries (faster failure detection)" $([ "$current_retries" -eq 5 ] && echo "on" || echo "off") \
                "8" "Medium retries" $([ "$current_retries" -eq 8 ] && echo "on" || echo "off") \
                "15" "Default retries" $([ "$current_retries" -eq 15 ] && echo "on" || echo "off") \
                "custom" "Custom value" "off")
              
              if [ -z "$new_retries" ]; then
                log "Retries selection cancelled"
                return
              fi
              
              if [ "$new_retries" = "custom" ]; then
                new_retries=$(dialog_input "Custom Retries" "Enter a custom retries value:" "$current_retries")
                
                if [ -z "$new_retries" ]; then
                  log "Custom retries input cancelled"
                  return
                fi
                
                # Validate input
                if ! [[ "$new_retries" =~ ^[0-9]+$ ]] || [ "$new_retries" -lt 1 ]; then
                  dialog_info "Invalid Value" "Retries must be a positive number."
                  log "Invalid retries value: $new_retries"
                  return
                fi
              fi
              
              # Set new value
              if [ "$new_retries" != "$current_retries" ]; then
                # Set current value
                sysctl -w net.ipv4.tcp_retries2=$new_retries
                
                # Make permanent
                if grep -q "net.ipv4.tcp_retries2" /etc/sysctl.conf; then
                  sed -i "s/net.ipv4.tcp_retries2=.*/net.ipv4.tcp_retries2=$new_retries/" /etc/sysctl.conf
                else
                  echo "net.ipv4.tcp_retries2=$new_retries" >> /etc/sysctl.conf
                fi
                
                log "TCP retries changed from $current_retries to $new_retries"
                dialog_info "Retries Changed" "TCP retries have been changed from $current_retries to $new_retries.\n\nThe change has been applied immediately and will persist after reboot."
              else
                dialog_info "No Change" "TCP retries is already set to $current_retries. No changes made."
                log "TCP retries unchanged from $current_retries"
              fi
              ;;
            resolver)
              # DNS resolver configuration
              if [ ! -f "/etc/resolv.conf" ]; then
                dialog_info "Not Available" "DNS resolver configuration file not found."
                log "resolv.conf not found"
                return
              fi
              
              # Current settings
              local current_nameservers=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
              local current_timeout=$(grep "^options timeout" /etc/resolv.conf | awk '{print $3}' || echo "default")
              local current_attempts=$(grep "^options attempts" /etc/resolv.conf | awk '{print $3}' || echo "default")
              
              # Show current settings
              dialog_info "Current DNS Settings" "Current DNS settings:\n\nNameservers: $current_nameservers\nTimeout: $current_timeout\nAttempts: $current_attempts"
              
              # Choose what to modify
              local resolver_option=$(dialog_menu "DNS Resolver" "Choose what to modify:" \
                "nameservers" "Change nameservers" \
                "timeout" "Set DNS query timeout" \
                "attempts" "Set DNS query attempts" \
                "back" "Back to DNS settings")
              
              if [ -z "$resolver_option" ] || [ "$resolver_option" = "back" ]; then
                log "Resolver option selection cancelled"
                return
              fi
              
              case $resolver_option in
                nameservers)
                  # Set nameservers
                  local nameserver_option=$(dialog_menu "Nameservers" "Choose nameserver option:" \
                    "google" "Google DNS (8.8.8.8, 8.8.4.4)" \
                    "cloudflare" "Cloudflare DNS (1.1.1.1, 1.0.0.1)" \
                    "opendns" "OpenDNS (208.67.222.222, 208.67.220.220)" \
                    "custom" "Custom nameservers" \
                    "back" "Cancel")
                  
                  if [ -z "$nameserver_option" ] || [ "$nameserver_option" = "back" ]; then
                    log "Nameserver option selection cancelled"
                    return
                  fi
                  
                  local nameservers=""
                  case $nameserver_option in
                    google)
                      nameservers="8.8.8.8 8.8.4.4"
                      ;;
                    cloudflare)
                      nameservers="1.1.1.1 1.0.0.1"
                      ;;
                    opendns)
                      nameservers="208.67.222.222 208.67.220.220"
                      ;;
                    custom)
                      nameservers=$(dialog_input "Custom Nameservers" "Enter custom nameservers (space-separated):" "$current_nameservers")
                      
                      if [ -z "$nameservers" ]; then
                        log "Custom nameservers input cancelled"
                        return
                      fi
                      ;;
                  esac
                  
                  # Backup current resolv.conf
                  cp /etc/resolv.conf "$BACKUP_DIR/network/resolv.conf.backup.$(date +%Y%m%d%H%M%S)"
                  
                  # Create new resolv.conf
                  local temp_resolv=$(mktemp)
                  
                  # Copy existing non-nameserver lines
                  grep -v "^nameserver" /etc/resolv.conf > "$temp_resolv"
                  
                  # Add new nameservers
                  for ns in $nameservers; do
                    echo "nameserver $ns" >> "$temp_resolv"
                  done
                  
                  # Replace resolv.conf
                  mv "$temp_resolv" /etc/resolv.conf
                  
                  log "DNS nameservers changed to: $nameservers"
                  dialog_info "Nameservers Changed" "DNS nameservers have been changed to:\n\n$nameservers"
                  ;;
                timeout)
                  # Set DNS timeout
                  local new_timeout=$(dialog_radiolist "DNS Timeout" "Current timeout: $current_timeout\n\nSelect a new value:" \
                    "1" "Fast timeout (1 second)" $([ "$current_timeout" -eq 1 ] && echo "on" || echo "off") \
                    "2" "Medium timeout (2 seconds)" $([ "$current_timeout" -eq 2 ] && echo "on" || echo "off") \
                    "5" "Default timeout (5 seconds)" $([ "$current_timeout" -eq 5 ] && echo "on" || echo "off") \
                    "10" "Slow timeout (10 seconds)" $([ "$current_timeout" -eq 10 ] && echo "on" || echo "off") \
                    "custom" "Custom value" "off")
                  
                  if [ -z "$new_timeout" ]; then
                    log "DNS timeout selection cancelled"
                    return
                  fi
                  
                  if [ "$new_timeout" = "custom" ]; then
                    new_timeout=$(dialog_input "Custom Timeout" "Enter a custom DNS timeout value (seconds):" "5")
                    
                    if [ -z "$new_timeout" ]; then
                      log "Custom DNS timeout input cancelled"
                      return
                    fi
                    
                    # Validate input
                    if ! [[ "$new_timeout" =~ ^[0-9]+$ ]] || [ "$new_timeout" -lt 1 ]; then
                      dialog_info "Invalid Value" "Timeout must be a positive number."
                      log "Invalid DNS timeout value: $new_timeout"
                      return
                    fi
                  fi
                  
                  # Backup current resolv.conf
                  cp /etc/resolv.conf "$BACKUP_DIR/network/resolv.conf.backup.$(date +%Y%m%d%H%M%S)"
                  
                  # Create new resolv.conf
                  local temp_resolv=$(mktemp)
                  
                  # Remove existing timeout option
                  grep -v "options timeout" /etc/resolv.conf > "$temp_resolv"
                  
                  # Find or add options line
                  if grep -q "^options " "$temp_resolv"; then
                    # Add timeout to existing options line
                    sed -i "/^options / s/$/ timeout:$new_timeout/" "$temp_resolv"
                  else
                    # Add new options line
                    echo "options timeout:$new_timeout" >> "$temp_resolv"
                  fi
                  
                  # Replace resolv.conf
                  mv "$temp_resolv" /etc/resolv.conf
                  
                  log "DNS timeout changed to: $new_timeout"
                  dialog_info "Timeout Changed" "DNS query timeout has been changed to $new_timeout seconds."
                  ;;
                attempts)
                  # Set DNS attempts
                  local new_attempts=$(dialog_radiolist "DNS Attempts" "Current attempts: $current_attempts\n\nSelect a new value:" \
                    "1" "Single attempt" $([ "$current_attempts" -eq 1 ] && echo "on" || echo "off") \
                    "2" "Two attempts" $([ "$current_attempts" -eq 2 ] && echo "on" || echo "off") \
                    "3" "Three attempts (default)" $([ "$current_attempts" -eq 3 ] && echo "on" || echo "off") \
                    "5" "Five attempts" $([ "$current_attempts" -eq 5 ] && echo "on" || echo "off") \
                    "custom" "Custom value" "off")
                  
                  if [ -z "$new_attempts" ]; then
                    log "DNS attempts selection cancelled"
                    return
                  fi
                  
                  if [ "$new_attempts" = "custom" ]; then
                    new_attempts=$(dialog_input "Custom Attempts" "Enter a custom DNS attempts value:" "3")
                    
                    if [ -z "$new_attempts" ]; then
                      log "Custom DNS attempts input cancelled"
                      return
                    fi
                    
                    # Validate input
                    if ! [[ "$new_attempts" =~ ^[0-9]+$ ]] || [ "$new_attempts" -lt 1 ]; then
                      dialog_info "Invalid Value" "Attempts must be a positive number."
                      log "Invalid DNS attempts value: $new_attempts"
                      return
                    fi
                  fi
                  
                  # Backup current resolv.conf
                  cp /etc/resolv.conf "$BACKUP_DIR/network/resolv.conf.backup.$(date +%Y%m%d%H%M%S)"
                  
                  # Create new resolv.conf
                  local temp_resolv=$(mktemp)
                  
                  # Remove existing attempts option
                  grep -v "options attempts" /etc/resolv.conf > "$temp_resolv"
                  
                  # Find or add options line
                  if grep -q "^options " "$temp_resolv"; then
                    # Add attempts to existing options line
                    sed -i "/^options / s/$/ attempts:$new_attempts/" "$temp_resolv"
                  else
                    # Add new options line
                    echo "options attempts:$new_attempts" >> "$temp_resolv"
                  fi
                  
                  # Replace resolv.conf
                  mv "$temp_resolv" /etc/resolv.conf
                  
                  log "DNS attempts changed to: $new_attempts"
                  dialog_info "Attempts Changed" "DNS query attempts has been changed to $new_attempts."
                  ;;
              esac
              ;;
          esac
          ;;
      esac
      ;;
    cpu)
      # CPU governor settings
      # Check if cpufreq is available
      if [ ! -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
        dialog_info "Not Supported" "CPU frequency scaling is not supported on this system."
        log "CPU frequency scaling not supported"
        return
      fi
      
      # Check if CPU frequency utilities are installed
      if ! command -v cpufreq-info &> /dev/null; then
        if dialog_confirm "Install Tools" "CPU frequency utilities are not installed. Would you like to install them?"; then
          apt update
          apt install -y cpufrequtils
          track_installed_package "cpufrequtils"
          log "CPU frequency utilities installed"
        else
          dialog_info "Tools Required" "CPU frequency utilities are required for governor settings."
          log "CPU frequency utilities installation cancelled"
          return
        fi
      fi
      
      # Get current governor
      local current_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
      
      # Get available governors
      local available_governors=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
      
      # Build governor options
      local governor_options=()
      for governor in $available_governors; do
        if [ "$governor" = "$current_governor" ]; then
          governor_options+=("$governor" "CPU Governor" "on")
        else
          governor_options+=("$governor" "CPU Governor" "off")
        fi
      done
      
      # Choose new governor
      local new_governor=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
        --title "CPU Governor" \
        --radiolist "Current governor: $current_governor\n\nSelect a new governor:" 15 70 10 \
        "${governor_options[@]}" 3>&1 1>&2 2>&3)
      
      if [ -z "$new_governor" ]; then
        log "Governor selection cancelled"
        return
      fi
      
      # Governor descriptions
      local governor_desc=""
      case $new_governor in
        performance)
          governor_desc="Maximum performance at all times (highest power consumption)"
          ;;
        powersave)
          governor_desc="Maximum power saving at all times (lowest performance)"
          ;;
        ondemand)
          governor_desc="Dynamically scales CPU frequency based on load"
          ;;
        conservative)
          governor_desc="Gradually scales CPU frequency based on load"
          ;;
        schedutil)
          governor_desc="Modern governor that uses CPU scheduler information"
          ;;
        userspace)
          governor_desc="Manually set frequency via userspace program"
          ;;
        *)
          governor_desc="Custom governor"
          ;;
      esac
      
      # Set new governor
      if [ "$new_governor" != "$current_governor" ]; then
        # Get number of CPU cores
        local cpu_count=$(nproc)
        
        # Set governor for all cores
        for ((i=0; i<$cpu_count; i++)); do
          echo "$new_governor" > "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor" 2>/dev/null
        done
        
        # Make permanent via cpufrequtils
        if [ -f "/etc/default/cpufrequtils" ]; then
          sed -i "s/^GOVERNOR=.*/GOVERNOR=\"$new_governor\"/" /etc/default/cpufrequtils
        else
          echo "GOVERNOR=\"$new_governor\"" > /etc/default/cpufrequtils
        fi
        
        log "CPU governor changed from $current_governor to $new_governor"
        dialog_info "Governor Changed" "CPU governor has been changed from $current_governor to $new_governor.\n\nDescription: $governor_desc\n\nThe change has been applied immediately and will persist after reboot."
      else
        dialog_info "No Change" "CPU governor is already set to $current_governor. No changes made."
        log "CPU governor unchanged from $current_governor"
      fi
      ;;
    filesystem)
      # Filesystem optimizations
      local fs_option=$(dialog_menu "Filesystem Optimization" "Choose a filesystem type to optimize:" \
        "ext4" "EXT4 filesystem" \
        "xfs" "XFS filesystem" \
        "btrfs" "Btrfs filesystem" \
        "all" "All supported filesystems" \
        "back" "Back to tuning menu")
      
      if [ -z "$fs_option" ] || [ "$fs_option" = "back" ]; then
        log "Filesystem option selection cancelled"
        return
      fi
      
      # Get mounted filesystems of selected type
      local filesystems=""
      case $fs_option in
        ext4|xfs|btrfs)
          filesystems=$(df -T | grep -i "$fs_option" | awk '{print $7 " (" $1 ")"}')
          ;;
        all)
          filesystems=$(df -T | grep -i -E 'ext4|xfs|btrfs' | awk '{print $7 " (" $1 ") [" $2 "]"}')
          ;;
      esac
      
      if [ -z "$filesystems" ]; then
        dialog_info "No Filesystems" "No $fs_option filesystems found."
        log "No $fs_option filesystems found"
        return
      fi
      
      # Choose optimization level
      local opt_level=$(dialog_radiolist "Optimization Level" "$fs_option filesystem(s) found:\n$filesystems\n\nSelect an optimization level:" \
        "basic" "Basic optimizations (safe)" "on" \
        "performance" "Performance optimizations" "off" \
        "aggressive" "Aggressive optimizations (use with caution)" "off" \
        "custom" "Custom mount options" "off")
      
      if [ -z "$opt_level" ]; then
        log "Optimization level selection cancelled"
        return
      fi
      
      # Get mount options based on filesystem type and optimization level
      local mount_options=""
      case $fs_option in
        ext4)
          case $opt_level in
            basic)
              mount_options="defaults,noatime"
              ;;
            performance)
              mount_options="defaults,noatime,commit=60,barrier=0"
              ;;
            aggressive)
              mount_options="defaults,noatime,commit=120,barrier=0,data=writeback"
              ;;
            custom)
              mount_options=$(dialog_input "Custom Mount Options" "Enter custom mount options for ext4 filesystem:" "defaults,noatime")
              
              if [ -z "$mount_options" ]; then
                log "Custom mount options input cancelled"
                return
              fi
              ;;
          esac
          ;;
        xfs)
          case $opt_level in
            basic)
              mount_options="defaults,noatime"
              ;;
            performance)
              mount_options="defaults,noatime,logbufs=8"
              ;;
            aggressive)
              mount_options="defaults,noatime,logbufs=8,logbsize=256k"
              ;;
            custom)
              mount_options=$(dialog_input "Custom Mount Options" "Enter custom mount options for XFS filesystem:" "defaults,noatime")
              
              if [ -z "$mount_options" ]; then
                log "Custom mount options input cancelled"
                return
              fi
              ;;
          esac
          ;;
        btrfs)
          case $opt_level in
            basic)
              mount_options="defaults,noatime"
              ;;
            performance)
              mount_options="defaults,noatime,compress=zstd:1"
              ;;
            aggressive)
              mount_options="defaults,noatime,compress=zstd:3,ssd"
              ;;
            custom)
              mount_options=$(dialog_input "Custom Mount Options" "Enter custom mount options for Btrfs filesystem:" "defaults,noatime")
              
              if [ -z "$mount_options" ]; then
                log "Custom mount options input cancelled"
                return
              fi
              ;;
          esac
          ;;
        all)
          dialog_info "Multiple Filesystems" "For multiple filesystem types, each will be optimized according to its type with the selected optimization level."
          ;;
      esac
      
      # Backup fstab
      cp /etc/fstab "$BACKUP_DIR/system_state/fstab.backup.$(date +%Y%m%d%H%M%S)"
      
      # Update fstab
      local update_count=0
      
      case $fs_option in
        ext4|xfs|btrfs)
          # Get list of filesystems to update
          local entries=$(df -T | grep -i "$fs_option" | awk '{print $1 " " $7}')
          
          while read -r device mountpoint; do
            # Get UUID
            local uuid=$(blkid -s UUID -o value "$device")
            
            if [ -n "$uuid" ]; then
              # Update fstab with the new mount options
              if grep -q "UUID=$uuid" /etc/fstab; then
                sed -i "/UUID=$uuid/ s/defaults[^[:space:]]*/`echo $mount_options`/" /etc/fstab
                update_count=$((update_count + 1))
              fi
            fi
          done <<< "$entries"
          ;;
        all)
          # Update each filesystem type with its appropriate options
          local ext4_entries=$(df -T | grep -i "ext4" | awk '{print $1 " " $7}')
          local xfs_entries=$(df -T | grep -i "xfs" | awk '{print $1 " " $7}')
          local btrfs_entries=$(df -T | grep -i "btrfs" | awk '{print $1 " " $7}')
          
# Set mount options based on filesystem type and optimization level
          local ext4_options=""
          local xfs_options=""
          local btrfs_options=""
          
          case $opt_level in
            basic)
              ext4_options="defaults,noatime"
              xfs_options="defaults,noatime"
              btrfs_options="defaults,noatime"
              ;;
            performance)
              ext4_options="defaults,noatime,commit=60,barrier=0"
              xfs_options="defaults,noatime,logbufs=8"
              btrfs_options="defaults,noatime,compress=zstd:1"
              ;;
            aggressive)
              ext4_options="defaults,noatime,commit=120,barrier=0,data=writeback"
              xfs_options="defaults,noatime,logbufs=8,logbsize=256k"
              btrfs_options="defaults,noatime,compress=zstd:3,ssd"
              ;;
            custom)
              ext4_options=$(dialog_input "Custom EXT4 Options" "Enter custom mount options for EXT4 filesystems:" "defaults,noatime")
              xfs_options=$(dialog_input "Custom XFS Options" "Enter custom mount options for XFS filesystems:" "defaults,noatime")
              btrfs_options=$(dialog_input "Custom Btrfs Options" "Enter custom mount options for Btrfs filesystems:" "defaults,noatime")
              ;;
          esac
          
          # Update ext4 filesystems
          while read -r device mountpoint; do
            # Get UUID
            local uuid=$(blkid -s UUID -o value "$device")
            
            if [ -n "$uuid" ]; then
              # Update fstab with the new mount options
              if grep -q "UUID=$uuid" /etc/fstab; then
                sed -i "/UUID=$uuid/ s/defaults[^[:space:]]*/`echo $ext4_options`/" /etc/fstab
                update_count=$((update_count + 1))
              fi
            fi
          done <<< "$ext4_entries"
          
          # Update xfs filesystems
          while read -r device mountpoint; do
            # Get UUID
            local uuid=$(blkid -s UUID -o value "$device")
            
            if [ -n "$uuid" ]; then
              # Update fstab with the new mount options
              if grep -q "UUID=$uuid" /etc/fstab; then
                sed -i "/UUID=$uuid/ s/defaults[^[:space:]]*/`echo $xfs_options`/" /etc/fstab
                update_count=$((update_count + 1))
              fi
            fi
          done <<< "$xfs_entries"
          
          # Update btrfs filesystems
          while read -r device mountpoint; do
            # Get UUID
            local uuid=$(blkid -s UUID -o value "$device")
            
            if [ -n "$uuid" ]; then
              # Update fstab with the new mount options
              if grep -q "UUID=$uuid" /etc/fstab; then
                sed -i "/UUID=$uuid/ s/defaults[^[:space:]]*/`echo $btrfs_options`/" /etc/fstab
                update_count=$((update_count + 1))
              fi
            fi
          done <<< "$btrfs_entries"
          ;;
      esac
      
      log "Filesystem optimizations applied to $update_count filesystems"
      dialog_info "Filesystems Optimized" "Mount options have been updated for $update_count filesystems.\n\nChanges will take effect after remounting filesystems or rebooting the system."
      
      # Ask if user wants to remount now
      if dialog_confirm "Remount Filesystems" "Do you want to remount the filesystems now to apply the changes?\n\nNote: This may disrupt active file operations."; then
        mount -a
        log "Filesystems remounted to apply new mount options"
        dialog_info "Filesystems Remounted" "All filesystems have been remounted with the new optimized settings."
      fi
      ;;
    services)
      # Disable unnecessary services
      local service_action=$(dialog_menu "Service Management" "Choose an action:" \
        "list" "List running services" \
        "disable" "Disable unnecessary services" \
        "prioritize" "Prioritize important services" \
        "back" "Back to tuning menu")
      
      if [ -z "$service_action" ] || [ "$service_action" = "back" ]; then
        log "Service action selection cancelled"
        return
      fi
      
      case $service_action in
        list)
          # List running services
          local services_output=$(systemctl list-units --type=service --state=running | head -n -7)
          dialog_info "Running Services" "$services_output"
          ;;
        disable)
          # Disable unnecessary services
          local service_list=""
          local temp_file=$(mktemp)
          
          # Get list of common unnecessary services
          systemctl list-units --type=service --all > "$temp_file"
          
          # Build list of potentially unnecessary services
          local unnecessary_services=()
          
          # Check for commonly unnecessary services (adjust based on your use case)
          for service in bluetooth cups printing avahi whoopsie ModemManager wpa_supplicant \
                        speech-dispatcher spice-vdagentd plymouth; do
            if grep -q "$service" "$temp_file"; then
              if systemctl is-active "$service" &>/dev/null; then
                unnecessary_services+=("$service.service" "Running" "on")
              else
                unnecessary_services+=("$service.service" "Not running" "off")
              fi
            fi
          done
          
          # Add other potentially unnecessary services
          if grep -q "snapd" "$temp_file"; then
            unnecessary_services+=("snapd.service" "Snap package management" "off")
          fi
          
          if grep -q "packagekit" "$temp_file"; then
            unnecessary_services+=("packagekit.service" "Package management service" "off")
          fi
          
          # Clean up
          rm -f "$temp_file"
          
          if [ ${#unnecessary_services[@]} -eq 0 ]; then
            dialog_info "No Services" "No commonly unnecessary services found on this system."
            log "No commonly unnecessary services found"
            return
          fi
          
          # Choose services to disable
          local services_to_disable=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
            --title "Disable Services" \
            --checklist "Select services to disable (may improve performance and reduce resource usage):" 20 70 15 \
            "${unnecessary_services[@]}" 3>&1 1>&2 2>&3)
          
          if [ -z "$services_to_disable" ]; then
            log "Service disable selection cancelled"
            return
          fi
          
          # Disable selected services
          for service in $services_to_disable; do
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            log "Service $service stopped and disabled"
          done
          
          log "Services disabled: $services_to_disable"
          dialog_info "Services Disabled" "The following services have been disabled:\n\n$services_to_disable\n\nThis may improve system performance and reduce resource usage."
          ;;
        prioritize)
          # Prioritize important services
          local service_list=""
          local temp_file=$(mktemp)
          
          # Get list of active services
          systemctl list-units --type=service --state=active | awk '{print $1}' | grep '\.service$' > "$temp_file"
          
          # Build list of important services
          local important_services=()
          
          # Check for common important services
          for service in sshd nginx apache2 mysql mariadb postgresql docker; do
            if grep -q "$service" "$temp_file"; then
              important_services+=("$service.service" "Service" "off")
            fi
          done
          
          # Clean up
          rm -f "$temp_file"
          
          if [ ${#important_services[@]} -eq 0 ]; then
            dialog_info "No Services" "No common services that can be prioritized were found on this system."
            log "No common important services found"
            return
          fi
          
          # Choose services to prioritize
          local services_to_prioritize=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
            --title "Prioritize Services" \
            --checklist "Select services to prioritize (these will receive higher CPU and I/O priority):" 20 70 15 \
            "${important_services[@]}" 3>&1 1>&2 2>&3)
          
          if [ -z "$services_to_prioritize" ]; then
            log "Service prioritize selection cancelled"
            return
          fi
          
          # Set nice and ionice for selected services
          for service in $services_to_prioritize; do
            # Create a service override file
            mkdir -p /etc/systemd/system/$service.d/
            
            cat > /etc/systemd/system/$service.d/priority.conf << EOL
[Service]
Nice=-10
IOSchedulingClass=1
IOSchedulingPriority=0
EOL
            
            # Reload and restart the service
            systemctl daemon-reload
            systemctl restart "$service" 2>/dev/null
            
            log "Service $service prioritized"
          done
          
          log "Services prioritized: $services_to_prioritize"
          dialog_info "Services Prioritized" "The following services have been prioritized:\n\n$services_to_prioritize\n\nThese services will now receive higher CPU and I/O priority."
          ;;
      esac
      ;;
    boot)
      # Optimize boot process
      local boot_option=$(dialog_menu "Boot Optimization" "Choose a boot optimization option:" \
        "services" "Disable unnecessary boot services" \
        "timeout" "Adjust GRUB timeout" \
        "parallel" "Enable parallel service startup" \
        "bootchart" "Analyze boot performance" \
        "back" "Back to tuning menu")
      
      if [ -z "$boot_option" ] || [ "$boot_option" = "back" ]; then
        log "Boot option selection cancelled"
        return
      fi
      
      case $boot_option in
        services)
          # Disable unnecessary boot services
          local temp_file=$(mktemp)
          
          # Get boot time of services
          systemd-analyze blame | head -20 > "$temp_file"
          
          # Display boot time analysis
          dialog_info "Boot Services" "Services that take the most time to start:\n\n$(cat "$temp_file")"
          
          # Create list of services that can be safely disabled at boot
          local boot_services=()
          
          # Common services that can be disabled or delayed
          for service in bluetooth cups printing avahi whoopsie ModemManager \
                        speech-dispatcher spice-vdagentd plymouth; do
            if systemctl list-unit-files | grep -q "$service"; then
              if systemctl is-enabled "$service" &>/dev/null; then
                boot_services+=("$service.service" "Boot service" "off")
              fi
            fi
          done
          
          # Add services from the blame list
          while read -r line; do
            local service=$(echo "$line" | awk '{print $2}')
            
            # Only include service units and exclude essential services
            if [[ "$service" == *.service ]] && ! [[ "$service" == *networkd* || "$service" == *systemd-* || "$service" == *user@* ]]; then
              # Check if it's not already in the list
              local found=0
              for ((i=0; i<${#boot_services[@]}; i+=3)); do
                if [ "${boot_services[$i]}" = "$service" ]; then
                  found=1
                  break
                fi
              done
              
              if [ $found -eq 0 ]; then
                boot_services+=("$service" "Boot service" "off")
              fi
            fi
          done < "$temp_file"
          
          # Clean up
          rm -f "$temp_file"
          
          if [ ${#boot_services[@]} -eq 0 ]; then
            dialog_info "No Services" "No boot services that can be safely disabled were found."
            log "No boot services found to disable"
            return
          fi
          
          # Choose services to disable at boot
          local services_to_disable=$(dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" \
            --title "Disable Boot Services" \
            --checklist "Select services to disable at boot (may improve boot time):" 20 70 15 \
            "${boot_services[@]}" 3>&1 1>&2 2>&3)
          
          if [ -z "$services_to_disable" ]; then
            log "Boot service disable selection cancelled"
            return
          fi
          
          # Disable selected services
          for service in $services_to_disable; do
            systemctl disable "$service" 2>/dev/null
            log "Boot service $service disabled"
          done
          
          log "Boot services disabled: $services_to_disable"
          dialog_info "Boot Services Disabled" "The following services have been disabled at boot:\n\n$services_to_disable\n\nThis may improve system boot time. You can still manually start these services when needed."
          ;;
        timeout)
          # Adjust GRUB timeout
          if [ ! -f "/etc/default/grub" ]; then
            dialog_info "GRUB Not Found" "GRUB configuration file not found. Cannot adjust timeout."
            log "GRUB configuration file not found"
            return
          fi
          
          # Get current timeout
          local current_timeout=$(grep ^GRUB_TIMEOUT= /etc/default/grub | cut -d= -f2)
          
          if [ -z "$current_timeout" ]; then
            current_timeout="Unknown"
          fi
          
          # Choose new timeout
          local new_timeout=$(dialog_radiolist "GRUB Timeout" "Current timeout: $current_timeout seconds\n\nSelect a new timeout:" \
            "0" "No timeout (boot immediately)" $([ "$current_timeout" -eq 0 ] 2>/dev/null && echo "on" || echo "off") \
            "1" "1 second" $([ "$current_timeout" -eq 1 ] 2>/dev/null && echo "on" || echo "off") \
            "3" "3 seconds" $([ "$current_timeout" -eq 3 ] 2>/dev/null && echo "on" || echo "off") \
            "5" "5 seconds (default)" $([ "$current_timeout" -eq 5 ] 2>/dev/null && echo "on" || echo "off") \
            "10" "10 seconds" $([ "$current_timeout" -eq 10 ] 2>/dev/null && echo "on" || echo "off") \
            "custom" "Custom value" "off")
          
          if [ -z "$new_timeout" ]; then
            log "GRUB timeout selection cancelled"
            return
          fi
          
          if [ "$new_timeout" = "custom" ]; then
            new_timeout=$(dialog_input "Custom Timeout" "Enter a custom GRUB timeout value (seconds):" "$current_timeout")
            
            if [ -z "$new_timeout" ]; then
              log "Custom GRUB timeout input cancelled"
              return
            fi
            
            # Validate input
            if ! [[ "$new_timeout" =~ ^[0-9]+$ ]]; then
              dialog_info "Invalid Value" "Timeout must be a positive number."
              log "Invalid GRUB timeout value: $new_timeout"
              return
            fi
          fi
          
          # Backup GRUB configuration
          cp /etc/default/grub "$BACKUP_DIR/system_state/grub.backup.$(date +%Y%m%d%H%M%S)"
          
          # Update GRUB timeout
          if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
            sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$new_timeout/" /etc/default/grub
          else
            echo "GRUB_TIMEOUT=$new_timeout" >> /etc/default/grub
          fi
          
          # Update GRUB
          update-grub
          
          log "GRUB timeout changed from $current_timeout to $new_timeout"
          dialog_info "GRUB Timeout Changed" "GRUB timeout has been changed from $current_timeout to $new_timeout seconds.\n\nThis change will take effect on the next reboot."
          ;;
        parallel)
          # Enable parallel service startup
          if ! grep -q "^DefaultTimeoutStartSec=" /etc/systemd/system.conf; then
            # Backup systemd configuration
            cp /etc/systemd/system.conf "$BACKUP_DIR/system_state/systemd.conf.backup.$(date +%Y%m%d%H%M%S)"
            
            # Update systemd configuration
            sed -i 's/^#DefaultTimeoutStartSec=90s/DefaultTimeoutStartSec=60s/' /etc/systemd/system.conf
            
            if ! grep -q "^DefaultTimeoutStartSec=" /etc/systemd/system.conf; then
              echo "DefaultTimeoutStartSec=60s" >> /etc/systemd/system.conf
            fi
            
            # Enable parallel startup
            if grep -q "^#DefaultTasksMax=" /etc/systemd/system.conf; then
              sed -i 's/^#DefaultTasksMax=.*/DefaultTasksMax=infinity/' /etc/systemd/system.conf
            else
              echo "DefaultTasksMax=infinity" >> /etc/systemd/system.conf
            fi
            
            log "Parallel service startup enabled"
            dialog_info "Parallel Startup" "Parallel service startup has been enabled.\n\nThis change will take effect on the next reboot."
          else
            dialog_info "Already Enabled" "Parallel service startup is already configured."
            log "Parallel service startup already configured"
          fi
          ;;
        bootchart)
          # Analyze boot performance
          if ! command -v bootchart &> /dev/null; then
            if dialog_confirm "Install Bootchart" "bootchart is not installed. Would you like to install it?"; then
              apt update
              apt install -y bootchart
              track_installed_package "bootchart"
              log "bootchart installed"
            else
              dialog_info "Bootchart" "bootchart is required for boot performance analysis."
              log "bootchart installation cancelled"
              return
            fi
          fi
          
          dialog_info "Bootchart" "Bootchart has been configured to analyze the boot process.\n\nAfter you reboot, it will generate a boot chart in /var/log/bootchart/.\n\nWould you like to reboot now to begin analysis?"
          
          if dialog_confirm "Reboot" "Do you want to reboot now to begin boot analysis?"; then
            log "System reboot requested for bootchart analysis"
            systemctl reboot
          fi
          ;;
      esac
      ;;
  esac
}

# Function for performance monitoring
monitor_performance() {
  log "Performance monitoring started"
  
  # Check if monitoring tools are installed
  local missing_tools=()
  
  for tool in htop dstat iotop; do
    if ! command -v $tool &> /dev/null; then
      missing_tools+=($tool)
    fi
  done
  
  if [ ${#missing_tools[@]} -gt 0 ]; then
    if dialog_confirm "Install Tools" "Some monitoring tools are not installed: ${missing_tools[*]}. Would you like to install them?"; then
      apt update
      
      for tool in "${missing_tools[@]}"; do
        apt install -y $tool
        track_installed_package "$tool"
        log "$tool installed"
      done
    else
      dialog_info "Tools Required" "Some monitoring tools may not be available."
      log "Monitoring tools installation cancelled"
    fi
  fi
  
  # Choose monitoring tool
  local tool=$(dialog_menu "Monitoring Tool" "Choose a performance monitoring tool:" \
    "htop" "Interactive process viewer" \
    "dstat" "System resource statistics" \
    "iotop" "I/O monitoring" \
    "vmstat" "Virtual memory statistics" \
    "back" "Back to performance menu")
  
  if [ -z "$tool" ] || [ "$tool" = "back" ]; then
    log "Monitoring tool selection cancelled"
    return
  fi
  
  # Run the selected tool
  case $tool in
    htop)
      if command -v htop &> /dev/null; then
        # Exit dialog temporarily to run htop
        clear
        echo -e "${YELLOW}Starting htop. Press 'q' to exit.${NC}"
        echo
        
        # Run htop
        htop
        
        # Return to dialog
        log "htop completed"
      else
        dialog_info "Tool Not Available" "htop is not installed."
        log "htop not installed"
      fi
      ;;
    dstat)
      if command -v dstat &> /dev/null; then
        # Ask for refresh interval
        local interval=$(dialog_input "Refresh Interval" "Enter the refresh interval in seconds:" "1")
        
        if [ -z "$interval" ]; then
          interval="1"
        fi
        
        # Ask for count
        local count=$(dialog_input "Sample Count" "Enter the number of samples (leave empty for continuous):" "10")
        
        # Exit dialog temporarily to run dstat
        clear
        echo -e "${YELLOW}Starting dstat with interval $interval seconds.${NC}"
        if [ -n "$count" ]; then
          echo -e "${YELLOW}Will collect $count samples. Press Ctrl+C to stop early.${NC}"
          dstat --time --cpu --mem --disk --net --load --proc $interval $count
        else
          echo -e "${YELLOW}Press Ctrl+C to stop.${NC}"
          dstat --time --cpu --mem --disk --net --load --proc $interval
        fi
        
        # Wait for user to acknowledge
        echo
        echo -e "${YELLOW}Monitoring completed. Press Enter to continue...${NC}"
        read
        
        # Return to dialog
        log "dstat completed"
      else
        dialog_info "Tool Not Available" "dstat is not installed."
        log "dstat not installed"
      fi
      ;;
    iotop)
      if command -v iotop &> /dev/null; then
        # Exit dialog temporarily to run iotop
        clear
        echo -e "${YELLOW}Starting iotop in batch mode. Press Ctrl+C to stop.${NC}"
        echo
        
        # Run iotop
        iotop -o -P -b -n 10 -d 1
        
        # Wait for user to acknowledge
        echo
        echo -e "${YELLOW}Monitoring completed. Press Enter to continue...${NC}"
        read
        
        # Return to dialog
        log "iotop completed"
      else
        dialog_info "Tool Not Available" "iotop is not installed."
        log "iotop not installed"
      fi
      ;;
    vmstat)
      # Ask for refresh interval
      local interval=$(dialog_input "Refresh Interval" "Enter the refresh interval in seconds:" "1")
      
      if [ -z "$interval" ]; then
        interval="1"
      fi
      
      # Ask for count
      local count=$(dialog_input "Sample Count" "Enter the number of samples (leave empty for continuous):" "10")
      
      # Exit dialog temporarily to run vmstat
      clear
      echo -e "${YELLOW}Starting vmstat with interval $interval seconds.${NC}"
      if [ -n "$count" ]; then
        echo -e "${YELLOW}Will collect $count samples. Press Ctrl+C to stop early.${NC}"
        vmstat $interval $count
      else
        echo -e "${YELLOW}Press Ctrl+C to stop.${NC}"
        vmstat $interval
      fi
      
      # Wait for user to acknowledge
      echo
      echo -e "${YELLOW}Monitoring completed. Press Enter to continue...${NC}"
      read
      
      # Return to dialog
      log "vmstat completed"
      ;;
  esac
}

# Function for performance tuning
tune_performance() {
  log "Performance tuning started"
  
  # Choose profile
  local profile=$(dialog_menu "Performance Profile" "Choose a performance profile to apply:" \
    "server" "Server profile (optimize for throughput)" \
    "desktop" "Desktop profile (optimize for responsiveness)" \
    "minimal" "Minimal resource usage (optimize for low memory)" \
    "custom" "Custom tuning" \
    "back" "Back to performance menu")
  
  if [ -z "$profile" ] || [ "$profile" = "back" ]; then
    log "Performance profile selection cancelled"
    return
  fi
  
  # Ask for confirmation
  if ! dialog_confirm "Apply Profile" "Are you sure you want to apply the $profile performance profile?\n\nThis will change multiple system settings at once."; then
    log "Performance profile confirmation cancelled"
    return
  fi
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR/system_state/performance"
  
  # Backup current settings
  cp /etc/sysctl.conf "$BACKUP_DIR/system_state/performance/sysctl.conf.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
  
  # Apply the selected profile
  case $profile in
    server)
      # Server profile
      (
        echo "10"; echo "XXX"; echo "Backing up current settings..."; echo "XXX"
        
        echo "20"; echo "XXX"; echo "Optimizing memory settings..."; echo "XXX"
        # Set swappiness
        sysctl -w vm.swappiness=10
        
        # VM dirty ratio
        sysctl -w vm.dirty_ratio=60
        sysctl -w vm.dirty_background_ratio=2
        
        echo "40"; echo "XXX"; echo "Optimizing network settings..."; echo "XXX"
        # Network settings
        sysctl -w net.core.somaxconn=4096
        sysctl -w net.core.netdev_max_backlog=4096
        sysctl -w net.ipv4.tcp_max_syn_backlog=4096
        sysctl -w net.ipv4.tcp_fin_timeout=30
        sysctl -w net.ipv4.tcp_keepalive_time=1200
        
        # TCP buffers
        sysctl -w net.core.rmem_max=16777216
        sysctl -w net.core.wmem_max=16777216
        sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
        sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"
        
        echo "60"; echo "XXX"; echo "Optimizing filesystem settings..."; echo "XXX"
        # File max
        sysctl -w fs.file-max=2097152
        
        # Adjust ulimit for the session
        ulimit -n 65536
        
        echo "80"; echo "XXX"; echo "Making settings permanent..."; echo "XXX"
        # Make settings permanent
        cat > /etc/sysctl.d/99-server-performance.conf << EOL
# Server performance optimization settings

# Memory settings
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2

# Network settings
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200

# TCP buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# File system settings
fs.file-max = 2097152
EOL
        
        # Set limits.conf for higher open files
        cat > /etc/security/limits.d/server-performance.conf << EOL
# Server performance limits
*               soft    nofile          65536
*               hard    nofile          65536
root            soft    nofile          65536
root            hard    nofile          65536
EOL
        
        echo "100"; echo "XXX"; echo "Server profile applied."; echo "XXX"
        
      ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Applying Server Profile" --gauge "Please wait..." 10 70 0
      
      log "Server performance profile applied"
      dialog_info "Profile Applied" "The server performance profile has been applied.\n\nThe system has been optimized for high throughput and network performance.\n\nSome changes may require a reboot to take full effect."
      ;;
    desktop)
      # Desktop profile
      (
        echo "10"; echo "XXX"; echo "Backing up current settings..."; echo "XXX"
        
        echo "20"; echo "XXX"; echo "Optimizing memory settings..."; echo "XXX"
        # Set swappiness
        sysctl -w vm.swappiness=10
        
        # VM dirty ratio
        sysctl -w vm.dirty_ratio=20
        sysctl -w vm.dirty_background_ratio=10
        
        echo "40"; echo "XXX"; echo "Optimizing I/O settings..."; echo "XXX"
        # I/O settings - if scheduler is available
        for disk in $(lsblk -d -n -o NAME | grep -v "loop" | grep -v "sr"); do
          if [ -f "/sys/block/$disk/queue/scheduler" ]; then
            if grep -q "bfq" /sys/block/$disk/queue/scheduler; then
              echo "bfq" > /sys/block/$disk/queue/scheduler
            elif grep -q "cfq" /sys/block/$disk/queue/scheduler; then
              echo "cfq" > /sys/block/$disk/queue/scheduler
            fi
          fi
        done
        
        echo "60"; echo "XXX"; echo "Optimizing CPU settings..."; echo "XXX"
        # Set CPU governor if available
        if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
          if grep -q "ondemand" /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors; then
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
              echo "ondemand" > $cpu 2>/dev/null
            done
          fi
        fi
        
        echo "80"; echo "XXX"; echo "Making settings permanent..."; echo "XXX"
        # Make settings permanent
        cat > /etc/sysctl.d/99-desktop-performance.conf << EOL
# Desktop performance optimization settings

# Memory settings
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10

# Interactive performance
kernel.sched_autogroup_enabled = 1
kernel.sched_child_runs_first = 1
EOL
        
        # Set I/O scheduler via udev
        cat > /etc/udev/rules.d/60-io-scheduler.rules << EOL
# Set I/O scheduler for improved desktop responsiveness
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="bfq"
EOL
        
        # Set CPU governor
        if [ -f "/etc/default/cpufrequtils" ]; then
          sed -i "s/^GOVERNOR=.*/GOVERNOR=\"ondemand\"/" /etc/default/cpufrequtils
        else
          echo "GOVERNOR=\"ondemand\"" > /etc/default/cpufrequtils
        fi
        
        echo "100"; echo "XXX"; echo "Desktop profile applied."; echo "XXX"
        
      ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Applying Desktop Profile" --gauge "Please wait..." 10 70 0
      
      log "Desktop performance profile applied"
      dialog_info "Profile Applied" "The desktop performance profile has been applied.\n\nThe system has been optimized for responsiveness and interactive use.\n\nSome changes may require a reboot to take full effect."
      ;;
    minimal)
      # Minimal resource profile
      (
        echo "10"; echo "XXX"; echo "Backing up current settings..."; echo "XXX"
        
        echo "20"; echo "XXX"; echo "Optimizing memory settings..."; echo "XXX"
        # Set swappiness
        sysctl -w vm.swappiness=60
        
        # VM dirty ratio
        sysctl -w vm.dirty_ratio=40
        sysctl -w vm.dirty_background_ratio=10
        
        # Memory overcommit
        sysctl -w vm.overcommit_memory=1
        sysctl -w vm.overcommit_ratio=50
        
        echo "40"; echo "XXX"; echo "Optimizing process settings..."; echo "XXX"
        # Process settings
        sysctl -w kernel.threads-max=4096
        
        echo "60"; echo "XXX"; echo "Optimizing I/O settings..."; echo "XXX"
        # Set lower I/O priority for background processes
        ionice -c 3 -p $(pidof systemd-journald) 2>/dev/null
        
        echo "80"; echo "XXX"; echo "Making settings permanent..."; echo "XXX"
        # Make settings permanent
        cat > /etc/sysctl.d/99-minimal-resources.conf << EOL
# Minimal resource usage optimization settings

# Memory settings
vm.swappiness = 60
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.overcommit_memory = 1
vm.overcommit_ratio = 50

# Process settings
kernel.threads-max = 4096
EOL
        
        # Create systemd service to set I/O priorities
        cat > /etc/systemd/system/set-io-priorities.service << EOL
[Unit]
Description=Set I/O priorities for background processes
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ionice -c 3 -p \$(/usr/bin/pidof systemd-journald)
ExecStart=/usr/bin/ionice -c 3 -p \$(/usr/bin/pidof systemd-udevd)
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL
        
        systemctl enable set-io-priorities.service
        
        echo "100"; echo "XXX"; echo "Minimal resource profile applied."; echo "XXX"
        
      ) | dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Applying Minimal Resource Profile" --gauge "Please wait..." 10 70 0
      
      log "Minimal resource profile applied"
      dialog_info "Profile Applied" "The minimal resource profile has been applied.\n\nThe system has been optimized for lower memory and CPU usage.\n\nSome changes may require a reboot to take full effect."
      ;;
    custom)
      # Custom tuning
      local tuning_option=$(dialog_menu "Custom Tuning" "Choose a tuning option:" \
        "swappiness" "Adjust swappiness (memory management)" \
        "io" "Configure I/O scheduler" \
        "network" "Tune network parameters" \
        "cpu" "CPU governor settings" \
        "back" "Back to performance menu")
      
      if [ -z "$tuning_option" ] || [ "$tuning_option" = "back" ]; then
        log "Custom tuning option selection cancelled"
        return
      fi
      
      # Call the appropriate tuning function
      case $tuning_option in
        swappiness|io|network|cpu)
          tune_system
          ;;
      esac
      ;;
  esac
}

# Function for performance management main menu
performance_management() {
  log "Performance management started"
  
  while true; do
    local action=$(dialog_menu "Performance Management" "Choose an option:" \
      "check" "Check system resources" \
      "tune" "System tuning options" \
      "monitor" "Performance monitoring" \
      "profile" "Apply performance profile" \
      "back" "Back to main menu")
    
    case $action in
      check)
        check_resources
        ;;
      tune)
        tune_system
        ;;
      monitor)
        monitor_performance
        ;;
      profile)
        tune_performance
        ;;
      back|"")
        log "Performance management exited"
        return
        ;;
    esac
  done
}

#######################################
# MAIN MENU
#######################################

# Main menu function
main_menu() {
  while true; do
    local choice=$(dialog_menu "Main Menu" "Welcome to $SCRIPT_NAME v$SCRIPT_VERSION\nEnhanced Ubuntu System Management Tool\n\nChoose an option:" \
      "update" "System Update" \
      "user" "User Management" \
      "ssh" "SSH Management" \
      "firewall" "Firewall Management" \
      "network" "Network Management" \
      "disk" "Disk Management" \
      "performance" "Performance Management" \
      "settings" "Script Settings" \
      "exit" "Exit")
    
    case $choice in
      update)
        update_system
        ;;
      user)
        user_management
        ;;
      ssh)
        ssh_management
        ;;
      firewall)
        firewall_management
        ;;
      network)
        network_management
        ;;
      disk)
        disk_management
        ;;
      performance)
        performance_management
        ;;
      settings)
        script_settings
        ;;
      exit|"")
        log "Script exited by user"
        exit 0
        ;;
    esac
  done
}

# Function for script settings
script_settings() {
  log "Script settings started"
  
  while true; do
    local action=$(dialog_menu "Script Settings" "Configure script behavior:" \
      "backup" "Backup directory settings" \
      "logs" "Logging settings" \
      "uninstall" "Remove all installed packages on exit" \
      "self" "Self-removal options" \
      "about" "About this script" \
      "back" "Back to main menu")
    
    case $action in
      backup)
        # Configure backup directory
        local current_dir="$BACKUP_DIR"
        local new_dir=$(dialog_input "Backup Directory" "Enter the path for the backup directory:" "$current_dir")
        
        if [ -z "$new_dir" ]; then
          log "Backup directory input cancelled"
        else
          # Update backup directory
          if [ "$new_dir" != "$current_dir" ]; then
            # Create new directory
            mkdir -p "$new_dir"
            
            # Copy existing backups if any
            if [ -d "$current_dir" ]; then
              cp -r "$current_dir"/* "$new_dir/" 2>/dev/null
            fi
            
            # Update variable
            BACKUP_DIR="$new_dir"
            LOG_DIR="$BACKUP_DIR/logs"
            MAIN_LOG="$LOG_DIR/main.log"
            
            # Create necessary subdirectories
            mkdir -p "$BACKUP_DIR/configs"
            mkdir -p "$BACKUP_DIR/logs"
            mkdir -p "$BACKUP_DIR/ssh_keys"
            mkdir -p "$BACKUP_DIR/system_state"
            mkdir -p "$BACKUP_DIR/firewall"
            mkdir -p "$BACKUP_DIR/network"
            mkdir -p "$BACKUP_DIR/disk"
            mkdir -p "$BACKUP_DIR/users"
            
            log "Backup directory changed to $new_dir"
            dialog_info "Backup Directory" "Backup directory has been changed to:\n$new_dir"
          else
            dialog_info "No Change" "Backup directory remains unchanged."
          fi
        fi
        ;;
      logs)
        # Configure logging
        local log_action=$(dialog_menu "Logging Settings" "Configure logging behavior:" \
          "view" "View current log" \
          "rotate" "Rotate logs now" \
          "keep" "Toggle keeping logs after exit" \
          "location" "Change logs location" \
          "back" "Back to settings menu")
        
        case $log_action in
          view)
            # View current log
            if [ -f "$MAIN_LOG" ]; then
              dialog --backtitle "$SCRIPT_NAME v$SCRIPT_VERSION" --title "Current Log" --textbox "$MAIN_LOG" 24 80
            else
              dialog_info "No Log" "No log file found."
            fi
            ;;
          rotate)
            # Rotate logs manually
            if [ -f "$MAIN_LOG" ]; then
              # Check if we already have 5 logs
              LOG_COUNT=$(ls "$LOG_DIR"/main*.log 2>/dev/null | wc -l)
              if [ "$LOG_COUNT" -ge 5 ]; then
                # Find and remove the oldest log
                OLDEST_LOG=$(ls -t "$LOG_DIR"/main*.log | tail -1)
                rm -f "$OLDEST_LOG"
              fi
              
              # Rename current log with timestamp
              mv "$MAIN_LOG" "$LOG_DIR/main_$(date +%Y%m%d%H%M%S).log"
              
              log "Logs rotated manually"
              dialog_info "Logs Rotated" "Logs have been rotated. A new log file has been created."
            else
              dialog_info "No Log" "No log file found to rotate."
            fi
            ;;
          keep)
            # Toggle keeping logs after exit
            if [ -f "$BACKUP_DIR/keep_logs" ]; then
              rm -f "$BACKUP_DIR/keep_logs"
              log "Log keeping disabled"
              dialog_info "Logs Setting" "Logs will be removed if self-removal is enabled."
            else
              touch "$BACKUP_DIR/keep_logs"
              log "Log keeping enabled"
              dialog_info "Logs Setting" "Logs will be kept even if self-removal is enabled."
            fi
            ;;
          location)
            # Change logs location
            local current_dir="$LOG_DIR"
            local new_dir=$(dialog_input "Logs Directory" "Enter the path for the logs directory:" "$current_dir")
            
            if [ -z "$new_dir" ]; then
              log "Logs directory input cancelled"
            else
              # Update logs directory
              if [ "$new_dir" != "$current_dir" ]; then
                # Create new directory
                mkdir -p "$new_dir"
                
                # Copy existing logs if any
                if [ -d "$current_dir" ]; then
                  cp -r "$current_dir"/* "$new_dir/" 2>/dev/null
                fi
                
                # Update variables
                LOG_DIR="$new_dir"
                MAIN_LOG="$LOG_DIR/main.log"
                
                log "Logs directory changed to $new_dir"
                dialog_info "Logs Directory" "Logs directory has been changed to:\n$new_dir"
              else
                dialog_info "No Change" "Logs directory remains unchanged."
              fi
            fi
            ;;
          back|"")
            # Return to settings menu
            ;;
        esac
        ;;
      uninstall)
        # Configure uninstall behavior
        if [ -f "$BACKUP_DIR/stealth_remove_packages" ]; then
          if dialog_confirm "Disable Package Removal" "Package removal on exit is currently ENABLED.\n\nDo you want to disable it?"; then
            rm -f "$BACKUP_DIR/stealth_remove_packages"
            log "Package removal on exit disabled"
            dialog_info "Package Removal" "Package removal on exit has been disabled."
          fi
        else
          if dialog_confirm "Enable Package Removal" "Package removal on exit is currently DISABLED.\n\nDo you want to enable it?\n\nThis will remove all packages installed by this script when you exit."; then
            touch "$BACKUP_DIR/stealth_remove_packages"
            log "Package removal on exit enabled"
            dialog_info "Package Removal" "Package removal on exit has been enabled.\n\nAll packages installed by this script will be removed when you exit."
          fi
        fi
        ;;
      self)
        # Configure self-removal
        if dialog_confirm "Self-Removal" "Do you want the script to remove itself when you exit?\n\nThis will delete the script file."; then
          SELF_REMOVE=1
          log "Self-removal enabled"
          dialog_info "Self-Removal" "Self-removal has been enabled. The script will delete itself when you exit."
        else
          SELF_REMOVE=0
          log "Self-removal disabled"
          dialog_info "Self-Removal" "Self-removal has been disabled. The script will remain after you exit."
        fi
        ;;
      about)
        # About this script
        local about_text="Enhanced Ubuntu Setup Script v$SCRIPT_VERSION\n\n"
        about_text+="A comprehensive system management tool for Ubuntu systems.\n\n"
        about_text+="This script provides a user-friendly interface for managing various aspects of your Ubuntu system:\n"
        about_text+="- System updates and configuration\n"
        about_text+="- User and group management\n"
        about_text+="- SSH configuration and key management\n"
        about_text+="- Firewall management\n"
        about_text+="- Network configuration\n"
        about_text+="- Disk management\n"
        about_text+="- Performance optimization\n\n"
        about_text+="All changes are backed up to: $BACKUP_DIR\n"
        about_text+="Logs are stored in: $LOG_DIR\n\n"
        about_text+="Script location: $SCRIPT_PATH"
        
        dialog_info "About" "$about_text"
        ;;
      back|"")
        log "Script settings exited"
        return
        ;;
    esac
  done
}

# Welcome message
dialog_info "Welcome" "Welcome to $SCRIPT_NAME v$SCRIPT_VERSION\n\nThis script will help you configure and manage various aspects of your Ubuntu system.\n\nAll changes will be backed up to: $BACKUP_DIR"

# Start the main menu
main_menu

# This point is reached only if main_menu exits unexpectedly
log "Script exited unexpectedly"
echo -e "${RED}The script exited unexpectedly. Please check the logs at $MAIN_LOG${NC}"

# Final cleanup
cleanup_and_exit

# Make script executable after download
# After downloading, run: chmod +x script_name.sh
# Then execute with: sudo ./script_name.sh

# END OF SCRIPT
