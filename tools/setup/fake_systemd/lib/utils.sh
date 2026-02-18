#!/bin/sh

# Logging Utilities
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

# INI Parser (Optimized with awk)
# Usage: parse_ini <file> <section> <key>
parse_ini() {
    local file="$1" section="$2" key="$3"
    [ -r "$file" ] || return 1

    awk -v s="[$section]" -v k="$key" '
        # Trim leading/trailing whitespace from line handled inside logic
        
        # Check section
        $0 ~ /^\[.*\]/ {
            # Trim brackets and spaces to compare section
            curr = $0;
            gsub(/^[ \t]+|[ \t]+$/, "", curr);
            if (curr == s) {
                in_section=1
            } else {
                in_section=0
            }
            next
        }

        # Match Key in Section
        in_section && /=/ {
            idx = index($0, "=");
            if (idx > 0) {
                line_key = substr($0, 1, idx-1);
                gsub(/^[ \t]+|[ \t]+$/, "", line_key);
                
                if (line_key == k) {
                    val = substr($0, idx+1);
                    gsub(/^[ \t]+|[ \t]+$/, "", val);
                    print val;
                    exit;
                }
            }
        }
    ' "$file"
}
