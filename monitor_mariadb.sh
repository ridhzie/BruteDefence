#!/bin/bash

# Log file to store IPs, usernames, and timestamps
LOG_FILE="/var/log/mariadb_access_attempts.log"

# Function to log and block IPs
block_ip() {
  IP="$1"
  USERNAME="$2"

  # Get the current timestamp
  CURRENT_TIMESTAMP=$(date +%s)

  # Count attempts within the last 15 minutes
  RECENT_ATTEMPTS=$(grep "$IP" "$LOG_FILE" | awk -v current="$CURRENT_TIMESTAMP" '{ split($4, a, "-"); if (a[1] > (current - 900)) print $0 }' | wc -l)

  # Calculate average attempts over the last hour
  AVG_ATTEMPTS_LAST_HOUR=$(awk -v current="$CURRENT_TIMESTAMP" '{ split($4, a, "-"); if (a[1] > (current - 3600)) print $0 }' "$LOG_FILE" | wc -l)
  AVG_ATTEMPTS_LAST_HOUR=$((AVG_ATTEMPTS_LAST_HOUR / 4))

  # Set the blocking threshold to half the average
  BLOCKING_THRESHOLD=$((AVG_ATTEMPTS_LAST_HOUR / 2))
  BLOCKING_THRESHOLD=$((BLOCKING_THRESHOLD < 5 ? 5 : BLOCKING_THRESHOLD))

  # Log the IP, username, and timestamp
  echo "$IP - $USERNAME - $(date +%s)" >> "$LOG_FILE"

  # Block the IP if recent attempts exceed the dynamic threshold
  if [ "$RECENT_ATTEMPTS" -gt "$BLOCKING_THRESHOLD" ]; then
    sudo iptables -A INPUT -s "$IP" -j DROP
    echo "Blocked IP: $IP targeting user: $USERNAME after exceeding threshold of $BLOCKING_THRESHOLD attempts within 15 minutes" >> "$LOG_FILE"
  fi
}

# Monitor MariaDB status
sudo journalctl -u mariadb -f |
  while IFS= read -r line; do
    if [[ "$line" == *"[Warning] Access denied for user"* ]]; then
      # Extract the IP
      IP=$(echo "$line" | rev | cut -d"'" -f2 | rev)
      # Extract the username
      USERNAME=$(echo "$line" | grep -oP "(?<=user ')[^']+" )

      # Log, analyze, and block if necessary
      block_ip "$IP" "$USERNAME"
    fi
  done
