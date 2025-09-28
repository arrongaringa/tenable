#!/usr/bin/env bash

# Script to find world-writable directories and add the sticky bit
# The sticky bit prevents users from deleting files they don't own

echo "Finding and securing world-writable directories..."

# Method 1: Simple and robust approach
find / -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o \
     -type d -perm -0002 ! -perm -1000 -print0 2>/dev/null | \
     while IFS= read -r -d '' dir; do
         echo "Adding sticky bit to: $dir"
         chmod +t "$dir"
     done

echo "Done!"

# Alternative method (closer to original but fixed):
# Get all local filesystem mount points, find world-writable dirs, add sticky bit
# df --local -P | awk 'NR>1 {print $6}' | \
# while read -r mountpoint; do
#     find "$mountpoint" -xdev -type d -perm -0002 ! -perm -1000 -print0 2>/dev/null | \
#     while IFS= read -r -d '' dir; do
#         echo "Adding sticky bit to: $dir"
#         chmod +t "$dir"
#     done
# done
