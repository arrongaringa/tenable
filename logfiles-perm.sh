#!/usr/bin/env bash

# Script to audit and fix log file permissions and ownership in /var/log
# This ensures log files have secure permissions and proper ownership

# Get minimum UID for regular users from system configuration
l_uidmin="$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)"
l_output2=""

# Function to test and fix file permissions and ownership
file_test_fix() {
    local l_op2=""
    local l_fuser="root"
    local l_fgroup="root"
    
    # Check if file permissions are too permissive
    if [ $(( l_mode & perm_mask )) -gt 0 ]; then
        l_op2="${l_op2}\n  - Mode: ${l_mode} should be ${maxperm} or more restrictive"
        l_op2="${l_op2}\n  - Removing excess permissions"
        chmod "${l_rperms}" "${l_fname}"
    fi
    
    # Check if file owner is correct
    if [[ ! "${l_user}" =~ ${l_auser} ]]; then
        l_op2="${l_op2}\n  - Owned by: ${l_user} should be owned by ${l_auser//|/ or }"
        l_op2="${l_op2}\n  - Changing ownership to: ${l_fuser}"
        chown "${l_fuser}" "${l_fname}"
    fi
    
    # Check if file group is correct
    if [[ ! "${l_group}" =~ ${l_agroup} ]]; then
        l_op2="${l_op2}\n  - Group owned by: ${l_group} should be group owned by ${l_agroup//|/ or }"
        l_op2="${l_op2}\n  - Changing group ownership to: ${l_fgroup}"
        chgrp "${l_fgroup}" "${l_fname}"
    fi
    
    # Add to output if changes were made
    if [ -n "${l_op2}" ]; then
        l_output2="${l_output2}\n- File: ${l_fname} issues:${l_op2}\n"
    fi
}

# Clear and initialize array for files that need checking
unset a_file
a_file=()

# Find log files that might have security issues:
# - Too permissive permissions (0137 = other write, group write, execute for all)
# - Not owned by root
# - Not group owned by root
while IFS= read -r -d $'\0' l_file; do
    if [ -e "${l_file}" ]; then
        a_file+=("$(stat -Lc '%n^%#a^%U^%u^%G^%g' "${l_file}")")
    fi
done < <(find -L /var/log -type f \( -perm /0137 -o ! -user root -o ! -group root \) -print0 2>/dev/null)

# Process each file found
while IFS='^' read -r l_fname l_mode l_user l_uid l_group l_gid; do
    [ -z "${l_fname}" ] && continue
    
    l_bname="$(basename "${l_fname}")"
    
    case "${l_bname}" in
        # Login tracking files (lastlog, wtmp, btmp)
        lastlog|lastlog.*|wtmp|wtmp.*|wtmp-*|btmp|btmp.*|btmp-*|README)
            perm_mask="0113"  # No execute for user/group, no write/execute for other
            maxperm="$(printf '%o' $((0777 & ~perm_mask)))"
            l_rperms="ug-x,o-wx"
            l_auser="root"
            l_agroup="(root|utmp)"
            file_test_fix
            ;;
        
        # Security and system logs
        secure|auth.log|syslog|messages)
            perm_mask="0137"  # No execute for user, no write/execute for group/other
            maxperm="$(printf '%o' $((0777 & ~perm_mask)))"
            l_rperms="u-x,g-wx,o-rwx"
            l_auser="(root|syslog)"
            l_agroup="(root|adm)"
            file_test_fix
            ;;
        
        # SSSD service logs
        SSSD|sssd)
            perm_mask="0117"
            maxperm="$(printf '%o' $((0777 & ~perm_mask)))"
            l_rperms="ug-x,o-rwx"
            l_auser="(root|SSSD)"
            l_agroup="(root|SSSD)"
            file_test_fix
            ;;
        
        # Display manager logs
        gdm|gdm3)
            perm_mask="0117"
            maxperm="$(printf '%o' $((0777 & ~perm_mask)))"
            l_rperms="ug-x,o-rwx"
            l_auser="root"
            l_agroup="(root|gdm|gdm3)"
            file_test_fix
            ;;
        
        # systemd journal files
        *.journal|*.journal~)
            perm_mask="0137"
            maxperm="$(printf '%o' $((0777 & ~perm_mask)))"
            l_rperms="u-x,g-wx,o-rwx"
            l_auser="root"
            l_agroup="(root|systemd-journal)"
            file_test_fix
            ;;
        
        # All other log files
        *)
            perm_mask="0137"
            maxperm="$(printf '%o' $((0777 & ~perm_mask)))"
            l_rperms="u-x,g-wx,o-rwx"
            l_auser="(root|syslog)"
            l_agroup="(root|adm)"
            
            # Special handling for files owned by system accounts
            if [ "${l_uid}" -lt "${l_uidmin}" ] && [ -z "$(awk -v grp="${l_group}" -F: '$1==grp {print $4}' /etc/group 2>/dev/null)" ]; then
                # Allow current user if it's a system account
                if [[ ! "${l_user}" =~ ${l_auser} ]]; then
                    l_auser="(root|syslog|${l_user})"
                fi
                
                # Check if group has any regular users
                if [[ ! "${l_group}" =~ ${l_agroup} ]]; then
                    l_tst=""
                    while read -r l_duid; do
                        [ "${l_duid}" -ge "${l_uidmin}" ] && l_tst="failed"
                    done <<< "$(awk -F: '$4=='"${l_gid}"' {print $3}' /etc/passwd 2>/dev/null)"
                    
                    # If no regular users in group, allow current group
                    [ "${l_tst}" != "failed" ] && l_agroup="(root|adm|${l_group})"
                fi
            fi
            
            file_test_fix
            ;;
    esac
done <<< "$(printf '%s\n' "${a_file[@]}")"

# Clear the array
unset a_file

# Print results
if [ -z "${l_output2}" ]; then
    echo "✓ All files in '/var/log/' have appropriate permissions and ownership"
    echo "✓ No changes required"
else
    echo "Log file security issues found and fixed:"
    echo -e "${l_output2}"
fi
