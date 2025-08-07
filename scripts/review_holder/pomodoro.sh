#!/usr/bin/env bash
#
# Pomodoro Timer - A simple, powerful Pomodoro timer for the command line
#
# Usage: ./pomodoro.sh [command] [options]
#   Commands:
#     start [task name]    - Start a new pomodoro session
#     pause                - Pause current session
#     resume               - Resume paused session
#     stop                 - Stop and save current session
#     status               - Show current timer status
#     watch                - Display timer in real-time
#     stats [day|week|month]- Show productivity statistics
#     config               - View/edit configuration
#
# Version: 1.0.0
# Author: Claude
# License: MIT

# Ensure script fails on error
set -e

# Get script name for proper display in messages
SCRIPT_NAME=$(basename "$0")

# =====================================================
# CONFIGURATION MANAGEMENT
# =====================================================

# Default configuration values
DEFAULT_WORK_MINUTES=25
DEFAULT_SHORT_BREAK=5
DEFAULT_LONG_BREAK=15
DEFAULT_CYCLES=4
DEFAULT_QUIET=false
DEFAULT_NO_NOTIFY=false

# Directories and files
CONFIG_DIR="$HOME/.pomo"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="$CONFIG_DIR/sessions.log"
CURRENT_SESSION_FILE="$CONFIG_DIR/current_session"
STATUS_FILE="$CONFIG_DIR/status"

# Initialize configuration directory and files if they don't exist
initialize_config() {
  if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
  fi
  
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
WORK_MINUTES=$DEFAULT_WORK_MINUTES
SHORT_BREAK=$DEFAULT_SHORT_BREAK
LONG_BREAK=$DEFAULT_LONG_BREAK
CYCLES=$DEFAULT_CYCLES
QUIET=$DEFAULT_QUIET
NO_NOTIFY=$DEFAULT_NO_NOTIFY
EOF
  fi
  
  # Ensure log file exists
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi
}

# Load configuration
load_config() {
  # Source the config file to load variables
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  else
    # Use defaults if config file doesn't exist
    WORK_MINUTES=$DEFAULT_WORK_MINUTES
    SHORT_BREAK=$DEFAULT_SHORT_BREAK
    LONG_BREAK=$DEFAULT_LONG_BREAK
    CYCLES=$DEFAULT_CYCLES
    QUIET=$DEFAULT_QUIET
    NO_NOTIFY=$DEFAULT_NO_NOTIFY
  fi
}

# Save configuration
save_config() {
  cat > "$CONFIG_FILE" << EOF
WORK_MINUTES=$WORK_MINUTES
SHORT_BREAK=$SHORT_BREAK
LONG_BREAK=$LONG_BREAK
CYCLES=$CYCLES
QUIET=$QUIET
NO_NOTIFY=$NO_NOTIFY
EOF
}

# Update single config value
update_config() {
  local key="$1"
  local value="$2"
  
  # Validate key
  case "$key" in
    WORK_MINUTES|SHORT_BREAK|LONG_BREAK|CYCLES)
      # Numeric validation
      if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Error: '$value' is not a valid number for $key"
        return 1
      fi
      ;;
    QUIET|NO_NOTIFY)
      # Boolean validation
      if [[ "$value" != "true" && "$value" != "false" ]]; then
        echo "Error: '$value' is not a valid boolean (true/false) for $key"
        return 1
      fi
      ;;
    *)
      echo "Error: Unknown configuration key '$key'"
      return 1
      ;;
  esac
  
  # Update config in memory
  eval "$key=$value"
  # Save to file
  save_config
  
  echo "Updated: $key = $value"
}

# Display configuration
show_config() {
  echo "Current Configuration:"
  echo "---------------------"
  echo "Work interval:         $WORK_MINUTES minutes"
  echo "Short break:           $SHORT_BREAK minutes"
  echo "Long break:            $LONG_BREAK minutes"
  echo "Cycles before long:    $CYCLES"
  echo "Audio notifications:   $(if [ "$QUIET" = "true" ]; then echo "Disabled"; else echo "Enabled"; fi)"
  echo "Desktop notifications: $(if [ "$NO_NOTIFY" = "true" ]; then echo "Disabled"; else echo "Enabled"; fi)"
}

# =====================================================
# NOTIFICATION FUNCTIONS
# =====================================================

# Terminal bell sound
sound_bell() {
  if [ "$QUIET" != "true" ]; then
    echo -e "\a"
  fi
}

# Desktop notification
send_notification() {
  local title="$1"
  local message="$2"
  
  if [ "$NO_NOTIFY" != "true" ]; then
    # Check for notify-send (Linux)
    if command -v notify-send &> /dev/null; then
      notify-send "$title" "$message"
    # Check for osascript (macOS)
    elif command -v osascript &> /dev/null; then
      osascript -e "display notification \"$message\" with title \"$title\""
    fi
  fi
  
  # Always show in terminal
  echo -e "\n$title: $message"
}

# =====================================================
# SESSION MANAGEMENT
# =====================================================

# Start a new session
start_session() {
  local task_name="$1"
  local timestamp=$(date +%s)
  local date_human=$(date +"%Y-%m-%d %H:%M:%S")
  
  # Create current session file
  cat > "$CURRENT_SESSION_FILE" << EOF
START_TIME=$timestamp
TASK_NAME="$task_name"
CURRENT_CYCLE=1
CURRENT_STATE=work
PAUSED=false
PAUSED_TIME=0
COMPLETED_POMODOROS=0
EOF

  echo "Starting Pomodoro session at $date_human"
  if [ -n "$task_name" ]; then
    echo "Task: $task_name"
  fi
  
  # Initialize status file
  update_status_file
  
  # Show initial timer
  run_timer
}

# Check if a session is already running
is_session_running() {
  if [ -f "$CURRENT_SESSION_FILE" ]; then
    source "$CURRENT_SESSION_FILE"
    if [ "$PAUSED" = "false" ]; then
      return 0  # true
    fi
  fi
  return 1  # false
}

# Check if a session is paused
is_session_paused() {
  if [ -f "$CURRENT_SESSION_FILE" ]; then
    source "$CURRENT_SESSION_FILE"
    if [ "$PAUSED" = "true" ]; then
      return 0  # true
    fi
  fi
  return 1  # false
}

# Update the status file with current session details
update_status_file() {
  if [ ! -f "$CURRENT_SESSION_FILE" ]; then
    return 1
  fi
  
  source "$CURRENT_SESSION_FILE"
  local current_time=$(date +%s)
  
  # If paused, just write basic info
  if [ "$PAUSED" = "true" ]; then
    cat > "$STATUS_FILE" << EOF
STATE=$CURRENT_STATE
CYCLE=$CURRENT_CYCLE
TOTAL_CYCLES=$CYCLES
PAUSED=true
PAUSED_TIME=$PAUSED_TIME
COMPLETED_POMODOROS=$COMPLETED_POMODOROS
TASK_NAME="$TASK_NAME"
TIMESTAMP=$current_time
EOF
    return 0
  fi
  
  # Calculate elapsed time and duration
  local elapsed_time=$((current_time - START_TIME))
  local state_duration
  
  if [ "$CURRENT_STATE" = "work" ]; then
    state_duration=$((WORK_MINUTES * 60))
  elif [ "$CURRENT_STATE" = "short_break" ]; then
    state_duration=$((SHORT_BREAK * 60))
  elif [ "$CURRENT_STATE" = "long_break" ]; then
    state_duration=$((LONG_BREAK * 60))
  fi
  
  # Calculate remaining time
  local remaining=$((state_duration - elapsed_time))
  if [ $remaining -lt 0 ]; then
    remaining=0
  fi
  
  local mins=$((remaining / 60))
  local secs=$((remaining % 60))
  
  # Write status file
  cat > "$STATUS_FILE" << EOF
STATE=$CURRENT_STATE
CYCLE=$CURRENT_CYCLE
TOTAL_CYCLES=$CYCLES
ELAPSED=$elapsed_time
TOTAL=$state_duration
REMAINING=$remaining
MINS=$mins
SECS=$secs
PAUSED=false
COMPLETED_POMODOROS=$COMPLETED_POMODOROS
TASK_NAME="$TASK_NAME"
TIMESTAMP=$current_time
EOF
}

# Pause current session
pause_session() {
  if is_session_running; then
    source "$CURRENT_SESSION_FILE"
    PAUSED=true
    PAUSED_TIME=$(date +%s)
    
    # Update session file
    sed -i "s/PAUSED=false/PAUSED=true/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
      sed -i'' -e "s/PAUSED=false/PAUSED=true/" "$CURRENT_SESSION_FILE"  # macOS compatibility
    
    echo "PAUSED_TIME=$PAUSED_TIME" >> "$CURRENT_SESSION_FILE"
    
    # Update status file
    update_status_file
    
    echo "Session paused at $(date +"%H:%M:%S")"
  else
    echo "No active session to pause."
  fi
}

# Resume paused session
resume_session() {
  if is_session_paused; then
    source "$CURRENT_SESSION_FILE"
    local current_time=$(date +%s)
    local pause_duration=$((current_time - PAUSED_TIME))
    
    # Adjust start time to account for pause duration
    START_TIME=$((START_TIME + pause_duration))
    PAUSED=false
    
    # Update session file (with macOS compatibility)
    sed -i "s/PAUSED=true/PAUSED=false/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
      sed -i'' -e "s/PAUSED=true/PAUSED=false/" "$CURRENT_SESSION_FILE"
    
    sed -i "s/START_TIME=.*/START_TIME=$START_TIME/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
      sed -i'' -e "s/START_TIME=.*/START_TIME=$START_TIME/" "$CURRENT_SESSION_FILE"
    
    # Update status file
    update_status_file
    
    echo "Session resumed at $(date +"%H:%M:%S")"
    
    # Resume timer
    run_timer
  else
    echo "No paused session to resume."
  fi
}

# Stop current session and log it
stop_session() {
  if [ -f "$CURRENT_SESSION_FILE" ]; then
    source "$CURRENT_SESSION_FILE"
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    # Format duration in human-readable format
    local hours=$((duration / 3600))
    local minutes=$(( (duration % 3600) / 60 ))
    local seconds=$((duration % 60))
    local human_duration=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
    
    # Log the session
    echo "$(date +"%Y-%m-%d %H:%M:%S")|$TASK_NAME|$COMPLETED_POMODOROS|$human_duration" >> "$LOG_FILE"
    
    # Remove current session file and status file
    rm -f "$CURRENT_SESSION_FILE" "$STATUS_FILE"
    
    echo "Session stopped. Completed $COMPLETED_POMODOROS pomodoro(s)."
    echo "Total session time: $human_duration"
  else
    echo "No session to stop."
  fi
}

# Get current session status
session_status() {
  if [ -f "$CURRENT_SESSION_FILE" ]; then
    source "$CURRENT_SESSION_FILE"
    local current_time=$(date +%s)
    
    if [ "$PAUSED" = "true" ]; then
      echo "Status: PAUSED"
      local pause_duration=$((current_time - PAUSED_TIME))
      local pause_mins=$((pause_duration / 60))
      local pause_secs=$((pause_duration % 60))
      echo "Paused for: ${pause_mins}m ${pause_secs}s"
    else
      echo "Status: ACTIVE"
      
      # Calculate remaining time
      local elapsed_time=$((current_time - START_TIME))
      local state_duration
      
      if [ "$CURRENT_STATE" = "work" ]; then
        state_duration=$((WORK_MINUTES * 60))
        echo "Current state: WORK (Cycle $CURRENT_CYCLE of $CYCLES)"
      elif [ "$CURRENT_STATE" = "short_break" ]; then
        state_duration=$((SHORT_BREAK * 60))
        echo "Current state: SHORT BREAK"
      elif [ "$CURRENT_STATE" = "long_break" ]; then
        state_duration=$((LONG_BREAK * 60))
        echo "Current state: LONG BREAK"
      fi
      
      local remaining=$((state_duration - elapsed_time))
      if [ $remaining -lt 0 ]; then
        remaining=0
      fi
      
      local mins=$((remaining / 60))
      local secs=$((remaining % 60))
      echo "Time remaining: ${mins}m ${secs}s"
    fi
    
    echo "Completed pomodoros: $COMPLETED_POMODOROS"
    if [ -n "$TASK_NAME" ]; then
      echo "Current task: $TASK_NAME"
    fi
    
    echo ""
    echo "Tip: Run './$SCRIPT_NAME watch' to monitor the timer in real-time."
  else
    echo "No active pomodoro session."
  fi
}

# =====================================================
# TIMER FUNCTIONS
# =====================================================

# Watch the timer in real-time without affecting it
watch_timer() {
  # === VALIDATION AND INITIALIZATION ===
  if [ ! -f "$CURRENT_SESSION_FILE" ]; then
    echo "No active pomodoro session."
    return 1
  fi
  
  # Ensure status file exists
  if [ ! -f "$STATUS_FILE" ]; then
    update_status_file
  fi
  
  if [ ! -f "$STATUS_FILE" ]; then
    echo "Unable to create status file. Make sure the timer is running."
    return 1
  fi

  # === TERMINAL CAPABILITY DETECTION ===
  # Check if terminal supports required features
  if [ -z "$(tput lines 2>/dev/null)" ] || [ -z "$(tput cols 2>/dev/null)" ]; then
    echo "Your terminal doesn't support required features for enhanced display."
    echo "Watch mode will continue with basic updates."
    local basic_mode=true
  else
    local basic_mode=false
  fi
  
  # === SAVE TERMINAL STATE ===
  # Save terminal state and hide cursor
  if [ "$basic_mode" = "false" ]; then
    tput smcup    # Save screen
    tput civis    # Hide cursor
  else
    echo -ne "\033[?25l" # Just hide cursor in basic mode
  fi
  
  # === SIGNAL HANDLING ===
  # Function to properly restore terminal on exit
  cleanup() {
    if [ "$basic_mode" = "false" ]; then
      tput cnorm   # Show cursor
      tput rmcup   # Restore screen
    else
      echo -ne "\033[?25h" # Show cursor in basic mode
    fi
    exit 0
  }
  
  # Trap signals for clean exit
  trap cleanup SIGINT SIGTERM EXIT
  
  # Handle window resize
  handle_resize() {
    # Get new terminal size
    term_width=$(tput cols)
    term_height=$(tput lines)
    # Force a full redraw
    force_redraw=true
  }
  trap handle_resize SIGWINCH

  # === STATE TRACKING ===
  # Initialize state variables
  local last_state=""
  local last_cycle=0
  local last_paused=false
  local last_mins=0
  local last_secs=0
  local last_progress=0
  local last_task=""
  local last_width=0
  local last_height=0
  local last_timestamp=0
  local last_completed=0

  # Get initial terminal size
  local term_width=$(tput cols)
  local term_height=$(tput lines)
  
  # Force full redraw on first run
  local force_redraw=true
  
  # Draw the static portion of the UI (borders, labels, etc.)
  draw_static_ui() {
    # Clear screen and position cursor at top-left
    tput clear
    tput cup 0 0
    
    # Get updated terminal dimensions
    local width=$(tput cols)
    local height=$(tput lines)
    
    # Draw top border 
    echo -ne "É"
    for ((i=0; i<width-2; i++)); do echo -ne "Í"; done
    echo -e "»"
    
    # Title bar
    local title="POMODORO TIMER"
    echo -ne "º \033[1m$title\033[0m"
    # We'll skip time in static UI, it will be filled in by dynamic updates
    
    # Store position for time update
    time_row=1
    time_col=$((width - 11)) # Allow space for HH:MM:SS
    
    tput cup 1 $time_col
    echo -ne "           º"
    
    # Draw separator
    tput cup 2 0
    echo -ne "Ì"
    for ((i=0; i<width-2; i++)); do echo -ne "Í"; done
    echo -e "¹"
    
    # Task area (placeholder - to be filled in by dynamic updates)
    tput cup 3 0
    echo -ne "º"
    tput cup 3 $((width-1))
    echo -e "º"
    
    # Store position for task update
    task_row=3
    task_col=2
    
    # State display area rows (to be filled by dynamic updates)
    local start_row=5
    for ((i=start_row; i<start_row+7; i++)); do
      tput cup $i 0
      echo -ne "º"
      tput cup $i $((width-1))
      echo -e "º"
    done
    
    # Store positions for dynamic elements
    state_title_row=$((start_row))
    state_title_col=2
    
    time_display_row=$((start_row+1))
    time_display_col=$(( width / 2 - 2 )) # Center the 00:00 time
    
    progress_row=$((start_row+3))
    progress_col=4
    progress_width=$((width - 8))
    
    cycle_row=$((start_row+5))
    cycle_col=2
    
    # Stats section separator
    stats_sep_row=$((start_row+7))
    tput cup $stats_sep_row 0
    echo -ne "Ì"
    for ((i=0; i<width-2; i++)); do echo -ne "Í"; done
    echo -e "¹"
    
    # Stats area
    tput cup $((stats_sep_row+1)) 0
    echo -ne "º Completed: "
    
    # Store position for pomodoro count
    pomo_row=$((stats_sep_row+1))
    pomo_col=13
    
    tput cup $((stats_sep_row+1)) $((width-1))
    echo -e "º"
    
    # Help section
    tput cup $((stats_sep_row+2)) 0
    echo -ne "Ì"
    for ((i=0; i<width-2; i++)); do echo -ne "Í"; done
    echo -e "¹"
    
    # Help text
    tput cup $((stats_sep_row+3)) 0
    echo -ne "º"
    local instructions="Press Ctrl+C to exit watch mode"
    local padding=$(( (width-2-${#instructions}) / 2 ))
    tput cup $((stats_sep_row+3)) $((padding+1))
    echo -ne "$instructions"
    tput cup $((stats_sep_row+3)) $((width-1))
    echo -e "º"
    
    # Bottom border
    tput cup $((stats_sep_row+4)) 0
    echo -ne "È"
    for ((i=0; i<width-2; i++)); do echo -ne "Í"; done
    echo -e "¼"
  }

  # Function to update time in header
  update_header_time() {
    local time_str=$(date '+%H:%M:%S')
    tput cup $time_row $time_col
    echo -ne "$time_str"
  }
  
  # Function to update task name display
  update_task() {
    local task="$1"
    # Skip if nothing changed
    if [ "$task" = "$last_task" ] && [ "$force_redraw" != "true" ]; then
      return
    fi
    
    local max_task_len=$((term_width - 15))
    if [ ${#task} -gt $max_task_len ]; then
      task="${task:0:$((max_task_len-3))}..."
    fi
    
    # Clear the line first
    tput cup $task_row 0
    echo -ne "º"
    tput cup $task_row 2
    echo -ne "Task: \033[1m$task\033[0m"
    # Clear to the end of the line
    tput cup $task_row 2
    printf "%-$((term_width-3))s" "Task: $(tput bold)$task$(tput sgr0)"
    tput cup $task_row $((term_width-1))
    echo -ne "º"
    
    last_task="$task"
  }
  
  # Function to update state display
  update_state_display() {
    local state="$1"
    local is_paused="$2"
    
    # Skip if nothing changed
    if [ "$state" = "$last_state" ] && [ "$is_paused" = "$last_paused" ] && [ "$force_redraw" != "true" ]; then
      return
    fi
    
    # Set state title based on the current state
    if [ "$is_paused" = "true" ]; then
      local state_title="P A U S E D"
      local color="\033[1;33m"  # Yellow for pause
    else
      if [ "$state" = "work" ]; then
        local state_title="W O R K"
        local color="\033[1;31m"  # Red for work
      elif [ "$state" = "short_break" ]; then
        local state_title="S H O R T   B R E A K"
        local color="\033[1;32m"  # Green for short break 
      else
        local state_title="L O N G   B R E A K"
        local color="\033[1;34m"  # Blue for long break
      fi
    fi
    
    # Center state text
    local padding=$(( (term_width-2-${#state_title}) / 2 ))
    
    # Clear the area first
    tput cup $state_title_row 1
    printf "%-$((term_width-2))s" " "
    
    # Print state title
    tput cup $state_title_row $((padding+1))
    echo -ne "$color$state_title\033[0m"
    
    last_state="$state"
    last_paused="$is_paused"
  }
  
  # Function to update timer display
  update_timer() {
    local mins="$1"
    local secs="$2"
    
    # Skip if nothing changed
    if [ "$mins" = "$last_mins" ] && [ "$secs" = "$last_secs" ] && [ "$force_redraw" != "true" ]; then
      return
    fi
    
    # Get color based on state
    if [ "$last_paused" = "true" ]; then
      local color="\033[1;33m"  # Yellow for pause
    else
      if [ "$last_state" = "work" ]; then
        local color="\033[1;31m"  # Red for work
      elif [ "$last_state" = "short_break" ]; then
        local color="\033[1;32m"  # Green for short break 
      else
        local color="\033[1;34m"  # Blue for long break
      fi
    fi
    
    local time_str=$(printf "%02d:%02d" $mins $secs)
    
    # Position and print
    tput cup $time_display_row $time_display_col
    echo -ne "$color\033[1m$time_str\033[0m"
    
    last_mins="$mins"
    last_secs="$secs"
  }
  
  # Function to update progress bar
  update_progress() {
    local elapsed="$1"
    local total="$2"
    
    # Calculate progress
    local progress=$((progress_width * elapsed / total))
    if [ $progress -gt $progress_width ]; then
      progress=$progress_width
    fi
    
    # Skip if nothing changed
    if [ "$progress" = "$last_progress" ] && [ "$force_redraw" != "true" ]; then
      return
    fi
    
    # Get color based on state
    if [ "$last_state" = "work" ]; then
      local color="\033[1;31m"  # Red for work
    elif [ "$last_state" = "short_break" ]; then
      local color="\033[1;32m"  # Green for short break 
    else
      local color="\033[1;34m"  # Blue for long break
    fi
    
    # Clear line first
    tput cup $progress_row 1
    printf "%-$((term_width-2))s" " "
    
    # Draw progress bar
    tput cup $progress_row $progress_col
    echo -ne "$color["
    for ((i=0; i<progress; i++)); do echo -ne "="; done
    if [ $progress -lt $progress_width ]; then
      # Add > character at progress point if not complete
      echo -ne ">"
      for ((i=progress+1; i<progress_width; i++)); do echo -ne " "; done
    fi
    echo -ne "]\033[0m"
    
    last_progress="$progress"
  }
  
  # Function to update cycle info
  update_cycle() {
    local cycle="$1"
    local total_cycles="$2"
    
    # Skip if nothing changed
    if [ "$cycle" = "$last_cycle" ] && [ "$force_redraw" != "true" ]; then
      return
    fi
    
    local cycle_info="Cycle $cycle of $total_cycles"
    local padding=$(( (term_width-2-${#cycle_info}) / 2 ))
    
    # Clear line first
    tput cup $cycle_row 1
    printf "%-$((term_width-2))s" " "
    
    # Print cycle info
    tput cup $cycle_row $padding
    echo -ne "$cycle_info"
    
    last_cycle="$cycle"
  }
  
  # Function to update completed pomodoros
  update_completed() {
    local completed="$1"
    
    # Skip if nothing changed
    if [ "$completed" = "$last_completed" ] && [ "$force_redraw" != "true" ]; then
      return
    fi
    
    # Clear the area
    tput cup $pomo_row $pomo_col
    printf "%-$((term_width-15))s" " "
    
    # Draw pomodoro indicators
    tput cup $pomo_row $pomo_col
    
    if [ $completed -eq 0 ]; then
      echo -ne "None yet"
    else
      local visible_count=$((completed > 10 ? 10 : completed))
      for ((i=0; i<visible_count; i++)); do
        echo -ne "?"
      done
      
      if [ $completed -gt 10 ]; then
        echo -ne " +$((completed - 10)) more"
      fi
    fi
    
    last_completed="$completed"
  }
  
  # Function to update pause duration
  update_pause_duration() {
    local pause_time="$1"
    local current_time=$(date +%s)
    local pause_duration=$((current_time - pause_time))
    local pause_mins=$((pause_duration / 60))
    local pause_secs=$((pause_duration % 60))
    
    # Calculate position for centering
    local pause_msg="Paused for: ${pause_mins}m ${pause_secs}s"
    local padding=$(( (term_width-2-${#pause_msg}) / 2 ))
    
    # Clear line
    tput cup $((time_display_row+1)) 1
    printf "%-$((term_width-2))s" " "
    
    # Show pause duration
    tput cup $((time_display_row+1)) $padding
    echo -ne "$pause_msg"
  }
  
  # === MAIN WATCH LOOP ===
  # Initial drawing of static UI
  if [ "$basic_mode" = "false" ]; then
    draw_static_ui
  else
    # For basic mode, just clear the screen
    clear
    echo "POMODORO TIMER (BASIC MODE)"
    echo "==========================="
  fi
  
  # Main loop
  while true; do
    # Check if session file still exists
    if [ ! -f "$STATUS_FILE" ]; then
      if [ "$basic_mode" = "false" ]; then
        tput cup $((term_height-2)) 0
        tput el  # Clear line
        echo "Session ended."
        sleep 2
      else
        echo "Session ended."
      fi
      cleanup
      return 0
    fi
    
    # Source the status file
    source "$STATUS_FILE"
    
    # Basic validation
    if [ -z "$TIMESTAMP" ] || [ -z "$STATE" ]; then
      sleep 0.5
      continue
    fi
    
    # Check if terminal was resized
    current_width=$(tput cols 2>/dev/null || echo $term_width)
    current_height=$(tput lines 2>/dev/null || echo $term_height)
    
    if [ "$current_width" != "$term_width" ] || [ "$current_height" != "$term_height" ]; then
      term_width=$current_width
      term_height=$current_height
      force_redraw=true
    fi
    
    # Update calculations
    local current_time=$(date +%s)
    
    # For active sessions, calculate accurate remaining time
    if [ "$PAUSED" != "true" ] && [ -n "$REMAINING" ]; then
      local time_since_update=$((current_time - TIMESTAMP))
      local adjusted_remaining=$((REMAINING - time_since_update))
      if [ $adjusted_remaining -lt 0 ]; then
        adjusted_remaining=0
      fi
      MINS=$((adjusted_remaining / 60))
      SECS=$((adjusted_remaining % 60))
    fi
    
    # BASIC MODE DISPLAY
    if [ "$basic_mode" = "true" ]; then
      clear
      echo "POMODORO TIMER (BASIC MODE)"
      echo "==========================="
      echo ""
      
      if [ -n "$TASK_NAME" ]; then
        echo "Task: $TASK_NAME"
      fi
      
      echo ""
      
      if [ "$PAUSED" = "true" ]; then
        echo "*** PAUSED ***"
        local pause_duration=$((current_time - PAUSED_TIME))
        local pause_mins=$((pause_duration / 60))
        local pause_secs=$((pause_duration % 60))
        echo "Paused for: ${pause_mins}m ${pause_secs}s"
      else
        if [ "$STATE" = "work" ]; then
          echo "STATE: WORK (Cycle $CYCLE of $TOTAL_CYCLES)"
        elif [ "$STATE" = "short_break" ]; then
          echo "STATE: SHORT BREAK"
        else
          echo "STATE: LONG BREAK"
        fi
        
        echo "Time remaining: ${MINS}m ${SECS}s"
        
        if [ -n "$ELAPSED" ] && [ -n "$TOTAL" ]; then
          local width=40
          local progress=$((width * ELAPSED / TOTAL))
          if [ $progress -gt $width ]; then
            progress=$width
          fi
          
          echo -n "["
          for ((i=0; i<progress; i++)); do echo -n "#"; done
          for ((i=progress; i<width; i++)); do echo -n " "; done
          echo "]"
        fi
      fi
      
      echo ""
      echo "Completed pomodoros: $COMPLETED_POMODOROS"
      echo ""
      echo "Press Ctrl+C to exit watch mode"
      
    # ENHANCED MODE DISPLAY
    else
      # Check if we need to redraw everything
      if [ "$force_redraw" = "true" ] || [ "$term_width" != "$last_width" ] || [ "$term_height" != "$last_height" ]; then
        # If yes, redraw static UI
        draw_static_ui
        last_width=$term_width
        last_height=$term_height
        force_redraw=false
      fi
      
      # Update header time
      update_header_time
      
      # Update task name
      if [ -n "$TASK_NAME" ]; then
        update_task "$TASK_NAME"
      else
        update_task "No task specified"
      fi
      
      # Update state section
      update_state_display "$STATE" "$PAUSED"
      
      # Handle different elements based on if paused or active
      if [ "$PAUSED" = "true" ]; then
        # Update pause time display
        update_timer "$MINS" "$SECS"
        update_pause_duration "$PAUSED_TIME"
      else
        # Active timer updates
        update_timer "$MINS" "$SECS"
        
        # Only update progress if we have the data
        if [ -n "$ELAPSED" ] && [ -n "$TOTAL" ]; then
          update_progress "$ELAPSED" "$TOTAL"
        fi
        
        # Update cycle info
        update_cycle "$CYCLE" "$TOTAL_CYCLES"
      fi
      
      # Update completed pomodoros
      update_completed "$COMPLETED_POMODOROS"
    fi
    
    # Update last timestamp
    last_timestamp=$TIMESTAMP
    
    # Sleep briefly (shorter refresh time for more responsive display)
    sleep 0.25
  done
  
  # Cleanup will be called automatically by trap
}

# Display timer progress
display_timer() {
  local elapsed=$1
  local total=$2
  local state=$3
  local cycle=$4
  
  # Clear line and move cursor to beginning
  echo -ne "\r\033[K"
  
  # Calculate remaining time
  local remaining=$((total - elapsed))
  if [ $remaining -lt 0 ]; then
    remaining=0
  fi
  
  local mins=$((remaining / 60))
  local secs=$((remaining % 60))
  
  # Create simple progress bar
  local width=20
  local progress_chars=$(( width * elapsed / total ))
  if [ $progress_chars -gt $width ]; then
    progress_chars=$width
  fi
  
  local progress_bar="["
  for ((i=0; i<progress_chars; i++)); do
    progress_bar+="#"
  done
  for ((i=progress_chars; i<width; i++)); do
    progress_bar+=" "
  done
  progress_bar+="]"
  
  # Display with color based on state
  if [ "$state" = "work" ]; then
    echo -ne "\033[1;31m" # Red for work
    state_display="WORK"
  elif [ "$state" = "short_break" ]; then
    echo -ne "\033[1;32m" # Green for short break
    state_display="SHORT BREAK"
  else
    echo -ne "\033[1;34m" # Blue for long break
    state_display="LONG BREAK"
  fi
  
  echo -ne "$state_display ($cycle/$CYCLES): ${mins}m ${secs}s $progress_bar"
  echo -ne "\033[0m" # Reset color
}

# The main timer function
run_timer() {
  # If not starting fresh, load the current session
  if [ -f "$CURRENT_SESSION_FILE" ]; then
    source "$CURRENT_SESSION_FILE"
  else
    echo "No active session. Use './$SCRIPT_NAME start' to begin."
    return 1
  fi
  
  # Exit if paused
  if [ "$PAUSED" = "true" ]; then
    echo "Session is paused. Use './$SCRIPT_NAME resume' to continue."
    return 0
  fi
  
  # Hide cursor
  echo -ne "\033[?25l"
  
  # Trap to handle clean exit
  trap 'echo -e "\n\033[?25h"; exit 0' SIGINT SIGTERM
  
  # Main timer loop
  while true; do
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - START_TIME))
    local state_duration
    
    # Determine current state duration
    if [ "$CURRENT_STATE" = "work" ]; then
      state_duration=$((WORK_MINUTES * 60))
    elif [ "$CURRENT_STATE" = "short_break" ]; then
      state_duration=$((SHORT_BREAK * 60))
    elif [ "$CURRENT_STATE" = "long_break" ]; then
      state_duration=$((LONG_BREAK * 60))
    fi
    
    # Check if need to transition to next state
    if [ $elapsed_time -ge $state_duration ]; then
      # State transition
      if [ "$CURRENT_STATE" = "work" ]; then
        # Increment completed pomodoros
        COMPLETED_POMODOROS=$((COMPLETED_POMODOROS + 1))
        
        # Check if it's time for a long break
        if [ $CURRENT_CYCLE -ge $CYCLES ]; then
          CURRENT_STATE="long_break"
          send_notification "Pomodoro Completed" "Take a long break ($LONG_BREAK minutes)"
        else
          CURRENT_STATE="short_break"
          send_notification "Pomodoro Completed" "Take a short break ($SHORT_BREAK minutes)"
        fi
      elif [ "$CURRENT_STATE" = "short_break" ]; then
        CURRENT_STATE="work"
        CURRENT_CYCLE=$((CURRENT_CYCLE + 1))
        send_notification "Break Ended" "Back to work (Cycle $CURRENT_CYCLE)"
      elif [ "$CURRENT_STATE" = "long_break" ]; then
        CURRENT_STATE="work"
        CURRENT_CYCLE=1
        send_notification "Long Break Ended" "Back to work (New set, Cycle $CURRENT_CYCLE)"
      fi
      
      # Reset timer
      START_TIME=$(date +%s)
      elapsed_time=0
      
      # Sound notification
      sound_bell
      
      # Update session file
      sed -i "s/CURRENT_CYCLE=.*/CURRENT_CYCLE=$CURRENT_CYCLE/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
        sed -i'' -e "s/CURRENT_CYCLE=.*/CURRENT_CYCLE=$CURRENT_CYCLE/" "$CURRENT_SESSION_FILE"
      
      sed -i "s/CURRENT_STATE=.*/CURRENT_STATE=$CURRENT_STATE/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
        sed -i'' -e "s/CURRENT_STATE=.*/CURRENT_STATE=$CURRENT_STATE/" "$CURRENT_SESSION_FILE"
      
      sed -i "s/START_TIME=.*/START_TIME=$START_TIME/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
        sed -i'' -e "s/START_TIME=.*/START_TIME=$START_TIME/" "$CURRENT_SESSION_FILE"
      
      sed -i "s/COMPLETED_POMODOROS=.*/COMPLETED_POMODOROS=$COMPLETED_POMODOROS/" "$CURRENT_SESSION_FILE" 2>/dev/null || 
        sed -i'' -e "s/COMPLETED_POMODOROS=.*/COMPLETED_POMODOROS=$COMPLETED_POMODOROS/" "$CURRENT_SESSION_FILE"
    fi
    
    # Display timer
    display_timer $elapsed_time $state_duration "$CURRENT_STATE" $CURRENT_CYCLE
    
    # Update status file (every 2 seconds to reduce disk I/O)
    if [ $((elapsed_time % 2)) -eq 0 ]; then
      update_status_file
    fi
    
    # Check for keyboard input (non-blocking)
    read -t 0.25 -N 1 input
    if [ $? -eq 0 ]; then
      case "$input" in
        p|P)
          echo -e "\nPausing session..."
          echo -ne "\033[?25h" # Show cursor
          pause_session
          return 0
          ;;
        r|R)
          # Only relevant if paused, but we handle it anyway
          echo -e "\nResuming session..."
          ;;
        s|S|q|Q)
          echo -e "\nStopping session..."
          echo -ne "\033[?25h" # Show cursor
          stop_session
          return 0
          ;;
      esac
    fi
    
    # Sleep briefly
    sleep 0.5
  done
  
  # Show cursor before exit (should be unreachable with loop)
  echo -ne "\033[?25h"
}

# =====================================================
# STATISTICS FUNCTIONS
# =====================================================

# Get statistics for a given time period
get_stats() {
  local period="$1"
  local filter_cmd=""
  
  case "$period" in
    day|today)
      # Today's date in YYYY-MM-DD format
      local today=$(date +"%Y-%m-%d")
      filter_cmd="grep '^$today'"
      period_display="Today ($today)"
      ;;
    week)
      # Calculate date 7 days ago
      local week_ago=$(date -d "7 days ago" +"%Y-%m-%d" 2>/dev/null || 
        date -v-7d +"%Y-%m-%d")  # macOS compatibility
      filter_cmd="awk -F'|' '\$1 >= \"$week_ago\"'"
      period_display="Last 7 days (since $week_ago)"
      ;;
    month)
      # Calculate date 30 days ago
      local month_ago=$(date -d "30 days ago" +"%Y-%m-%d" 2>/dev/null || 
        date -v-30d +"%Y-%m-%d")  # macOS compatibility
      filter_cmd="awk -F'|' '\$1 >= \"$month_ago\"'"
      period_display="Last 30 days (since $month_ago)"
      ;;
    all|"")
      # No filtering
      filter_cmd="cat"
      period_display="All time"
      ;;
    *)
      echo "Unknown period: $period"
      echo "Use: day, week, month, or all"
      return 1
      ;;
  esac
  
  # Apply filter and calculate stats
  local filtered_data=$(eval "$filter_cmd $LOG_FILE" 2>/dev/null || echo "")
  
  # If no data, return early
  if [ -z "$filtered_data" ]; then
    echo "No data available for $period_display"
    return 0
  fi
  
  # Count total sessions
  local total_sessions=$(echo "$filtered_data" | wc -l)
  
  # Sum completed pomodoros
  local total_pomodoros=$(echo "$filtered_data" | awk -F'|' '{sum += $3} END {print sum}')
  
  # Calculate total time
  local total_seconds=$(echo "$filtered_data" | awk -F'|' '
    {
      split($4, time, ":")
      seconds = time[1] * 3600 + time[2] * 60 + time[3]
      total += seconds
    }
    END {
      print total
    }')
  
  # Convert to hours, minutes, seconds
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))
  
  # Display stats
  echo "Pomodoro Statistics: $period_display"
  echo "-------------------------------"
  echo "Total sessions: $total_sessions"
  echo "Total pomodoros: $total_pomodoros"
  echo "Total time: ${hours}h ${minutes}m ${seconds}s"
  
  # Calculate average pomodoros per session
  if [ $total_sessions -gt 0 ]; then
    local avg_pomodoros=$(echo "scale=1; $total_pomodoros / $total_sessions" | bc)
    echo "Average pomodoros per session: $avg_pomodoros"
  fi
  
  # Show most frequent tasks if any
  if [ $total_sessions -gt 0 ]; then
    echo -e "\nMost frequent tasks:"
    echo "$filtered_data" | awk -F'|' '$2 != "" {count[$2]++} END {for (task in count) print count[task], task}' | sort -rn | head -5 | nl
  fi
}

# =====================================================
# COMMAND PROCESSING
# =====================================================

# Process command line arguments
process_args() {
  local command="$1"
  shift
  
  # Process options and store task name
  local task_name=""
  local option_args=()
  
  for arg in "$@"; do
    if [[ "$arg" == --* ]]; then
      option_args+=("$arg")
    elif [ -z "$task_name" ]; then
      task_name="$arg"
    else
      task_name="$task_name $arg"
    fi
  done
  
  # Process command
  case "$command" in
    start)
      # Process options
      for opt in "${option_args[@]}"; do
        case "$opt" in
          --work=*)
            update_config "WORK_MINUTES" "${opt#*=}"
            ;;
          --short=*)
            update_config "SHORT_BREAK" "${opt#*=}"
            ;;
          --long=*)
            update_config "LONG_BREAK" "${opt#*=}"
            ;;
          --cycles=*)
            update_config "CYCLES" "${opt#*=}"
            ;;
          --quiet)
            update_config "QUIET" "true"
            ;;
          --no-notify)
            update_config "NO_NOTIFY" "true"
            ;;
          *)
            echo "Unknown option: $opt"
            exit 1
            ;;
        esac
      done
      
      # Check if already running
      if is_session_running; then
        echo "A pomodoro session is already running."
        echo "Use './$SCRIPT_NAME status' to see current status or './$SCRIPT_NAME stop' to end it."
        return 1
      elif is_session_paused; then
        echo "A paused session exists. Use './$SCRIPT_NAME resume' to continue or './$SCRIPT_NAME stop' to end it."
        return 1
      else
        start_session "$task_name"
      fi
      ;;
    
    pause)
      pause_session
      ;;
    
    resume)
      resume_session
      ;;
    
    stop)
      stop_session
      ;;
    
    status)
      session_status
      ;;
    
    watch)
      watch_timer
      ;;
    
    stats)
      get_stats "$1"
      ;;
    
    config)
      if [ -n "$1" ] && [ -n "$2" ]; then
        # Update specific config
        update_config "${1^^}" "$2"
      else
        # Show config
        show_config
      fi
      ;;
    
    help|"")
      echo "Pomodoro Timer for the Command Line"
      echo ""
      echo "Usage: ./$SCRIPT_NAME [command] [options]"
      echo ""
      echo "Commands:"
      echo "  start [task]    Start a new pomodoro session"
      echo "  pause           Pause current session"
      echo "  resume          Resume paused session"
      echo "  stop            Stop and save current session"
      echo "  status          Display current session status"
      echo "  watch           Display timer in real-time (in a separate window)"
      echo "  stats [period]  Show statistics (day, week, month, all)"
      echo "  config [key] [value]  View or update configuration"
      echo "  help            Show this help message"
      echo ""
      echo "Options for 'start' command:"
      echo "  --work=MINUTES  Set work interval length"
      echo "  --short=MINUTES Set short break length"
      echo "  --long=MINUTES  Set long break length"
      echo "  --cycles=NUMBER Set cycles before long break"
      echo "  --quiet         Disable audio notifications"
      echo "  --no-notify     Disable desktop notifications"
      echo ""
      echo "During a session, you can use these keys:"
      echo "  p - Pause the session"
      echo "  r - Resume the session"
      echo "  s/q - Stop the session"
      ;;
    
    *)
      echo "Unknown command: $command"
      echo "Use './$SCRIPT_NAME help' for usage information."
      return 1
      ;;
  esac
}

# =====================================================
# MAIN EXECUTION
# =====================================================

# Main function
main() {
  # Initialize config directory and files
  initialize_config
  
  # Load configuration
  load_config
  
  # Process arguments
  process_args "$@"
}

# Run main with all arguments
main "$@"
