#!/bin/bash

# Log file to store IPs and timestamps
LOG_FILE="/var/log/mariadb_access_attempts.log"

# Function to log and block IPs
block_ip() {
  IP=$1
  ATTEMPTS=$(grep -c "$IP" $LOG_FILE)

  # Log the IP and timestamp
  echo "$IP - $(date +%s)" >> $LOG_FILE

  # Block the IP if attempts are greater than 10 within 30 minutes
  if [ $ATTEMPTS -gt 10 ]; then
    sudo iptables -A INPUT -s $IP -j DROP
    echo "Blocked IP: $IP after $ATTEMPTS attempts within 30 minutes" >> $LOG_FILE
  fi
}

# Monitor MariaDB status
sudo journalctl -u mariadb -f |
  while IFS= read -r line; do
    if [[ $line == *"[Warning] Access denied for user"* ]]; then
      # Extract the IP
      IP=$(echo $line | grep -oP "(?<=@)[0-9.]+")

      # Get the current timestamp
      CURRENT_TIMESTAMP=$(date +%s)

      # Remove entries older than 30 minutes (1800 seconds)
      awk -v current="$CURRENT_TIMESTAMP" '{ split($3, a, "-"); if (a[2] > (current - 1800)) print $0 }' $LOG_FILE > temp.log && mv temp.log $LOG_FILE

      # Log and block if necessary
      block_ip $IP
    fi
  done
