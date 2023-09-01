#!/bin/bash

LOG_FILE="/var/log/mariadb_access_attempts.log"
DEBUG_FILE="/var/log/mdb_brutedefence_debug.log"

# Whitelisted usernames
WHITELIST=("user_name_0" "user_name_1")

block_ip() {
  IDENTIFIER="$1"
  USERNAME="$2"

  # Check if the identifier is an IP or hostname
  if [[ "$IDENTIFIER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IP="$IDENTIFIER"
  else
    # Resolve the hostname to an IP
    IP=$(getent hosts "$IDENTIFIER" | awk '{print $1}')
  fi

  # If the username is not in the whitelist, block the IP immediately
  if [[ ! " ${WHITELIST[@]} " =~ " ${USERNAME} " ]]; then
    sudo iptables -A INPUT -s "$IP" -j DROP
    echo "Blocked IP: $IP ($IDENTIFIER) due to non-whitelisted username: $USERNAME" >> "$LOG_FILE"
    return
  fi


  # If the hostname cannot be resolved, skip the blocking logic
  [ -z "$IP" ] && return

  # Get the current timestamp
  CURRENT_TIMESTAMP=$(date +%s)

  # Count attempts within the last 15 minutes
  RECENT_ATTEMPTS=$(grep "$IP" "$LOG_FILE" | awk -v current="$CURRENT_TIMESTAMP" '{ if ($4 > (current - 900)) print $0 }' | wc -l)

  # Calculate average attempts over the last hour
  AVG_ATTEMPTS_LAST_HOUR=$(grep "$IP" "$LOG_FILE" | awk -v current="$CURRENT_TIMESTAMP" '{ if ($4 > (current - 3600)) print $0 }' | wc -l)
  AVG_ATTEMPTS_LAST_HOUR=$((AVG_ATTEMPTS_LAST_HOUR / 4))

  # Set the blocking threshold to half the average
  BLOCKING_THRESHOLD=$((AVG_ATTEMPTS_LAST_HOUR / 2))
  BLOCKING_THRESHOLD=$((BLOCKING_THRESHOLD < 5 ? 5 : BLOCKING_THRESHOLD))

  # Debugging statements
  echo "Debug: IP: $IP, RECENT_ATTEMPTS: $RECENT_ATTEMPTS, AVG_ATTEMPTS_LAST_HOUR: $AVG_ATTEMPTS_LAST_HOUR, BLOCKING_THRESHOLD: $BLOCKING_THRESHOLD" >> "$DEBUG_FILE"


  # Log the IP, username, timestamp, and current threshold
  echo "$IDENTIFIER - $IP - $USERNAME - $(date +%s) - Current Threshold: $BLOCKING_THRESHOLD" >> "$LOG_FILE"

  # Block the IP if recent attempts exceed the dynamic threshold
  if [ "$RECENT_ATTEMPTS" -gt "$BLOCKING_THRESHOLD" ]; then
    sudo iptables -A INPUT -s "$IP" -j DROP
    echo "Blocked IP: $IP ($IDENTIFIER) targeting user: $USERNAME after exceeding threshold of $BLOCKING_THRESHOLD attempts within 15 minutes" >> "$LOG_FILE"
  fi
}

# Monitor MariaDB status
sudo journalctl -u mariadb -f |
  while IFS= read -r line; do
    if [[ "$line" == *"[Warning] Access denied for user"* ]]; then
      # Extract the identifier (could be hostname or IP) and username
      IDENTIFIER=$(echo "$line" | sed -n "s/.*@'\([^']*\)'.*/\1/p")
      USERNAME=$(echo "$line" | awk -F"'" '{print $(NF-3)}')

      # Log, analyze, and block if necessary
      block_ip "$IDENTIFIER" "$USERNAME"
    fi
  done

