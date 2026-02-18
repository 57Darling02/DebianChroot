#!/bin/sh

# Deployment Logic
# Links the current script as 'systemctl' in a standard bin directory
# Interactive and automatic modes

deploy_systemctl_interactive() {
    # 1. Detect candidate directories
    local candidates=""
    
    # Termux
    if [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ]; then
        candidates="$candidates $PREFIX/bin"
    fi
    
    # Standard Linux
    if [ -d "/usr/local/bin" ]; then
        candidates="$candidates /usr/local/bin"
    fi
    if [ -d "/usr/bin" ]; then
        candidates="$candidates /usr/bin"
    fi
    if [ -d "/bin" ]; then
        candidates="$candidates /bin"
    fi
    
    # User local
    if [ -d "$HOME/.local/bin" ]; then
        candidates="$candidates $HOME/.local/bin"
    fi

    # Filter for writable
    local writable_candidates=""
    for dir in $candidates; do
        if [ -w "$dir" ]; then
             # Simple dedup check (not perfect but enough)
             case " $writable_candidates " in
                *" $dir "*) ;;
                *) writable_candidates="$writable_candidates $dir" ;;
             esac
        fi
    done

    if [ -z "$writable_candidates" ]; then
        log_error "No writable bin directories found in PATH."
        return 1
    fi

    # 2. Select Directory
    local target_dir=""
    # Take the first one as default
    set -- $writable_candidates
    local default_dir="$1"

    echo "Detected writable installation paths:"
    local i=1
    for dir in $writable_candidates; do
        echo "  [$i] $dir"
        i=$((i+1))
    done
    
    printf "Select installation directory [1]: "
    read choice
    if [ -z "$choice" ]; then
        choice=1
    fi

    # Map choice to directory
    i=1
    for dir in $writable_candidates; do
        if [ "$i" -eq "$choice" ]; then
            target_dir="$dir"
            break
        fi
        i=$((i+1))
    done

    if [ -z "$target_dir" ]; then
        log_error "Invalid selection."
        return 1
    fi

    echo "Selected: $target_dir"

    # 3. Create systemctl symlink
    local sysctl_link="$target_dir/systemctl"
    printf "Create '$sysctl_link' symlink? [Y/n] "
    read confirm
    case "$confirm" in
        [nN]*) ;;
        *)
            log_info "Creating $sysctl_link -> $REAL_PATH"
            rm -f "$sysctl_link"
            ln -sf "$REAL_PATH" "$sysctl_link"
            if [ $? -eq 0 ]; then
                log_success "Created 'systemctl' command."
            else
                log_error "Failed to create symlink."
            fi
            ;;
    esac

    # 4. Replace 'sv' (Optional)
    # Check if sv exists and is not our internal one
    local sys_sv="$target_dir/sv"
    
    # We only offer to replace if it's safe or user wants to override
    printf "Create/Override '$sys_sv' with fake_systemd's sv? (Recommended for unified management) [y/N] "
    read confirm
    case "$confirm" in
        [yY]*)
            # We link to OUR INTERNAL BIN/SV wrapper
            # But wait, our internal bin/sv is a symlink to busybox
            # It's better to link to busybox directly? No, link to our wrapper logic?
            # Actually, we should link to $BIN_DIR/sv (which is a symlink to busybox)
            # OR we create a wrapper script that sets environment variables?
            # 
            # If we just link to busybox, it won't know about SV_REPO/SV_ACTIVE unless we set env vars globally.
            # But 'sv' command takes path argument usually.
            # If user runs 'sv status nginx', standard sv looks in /etc/service.
            # Our busybox sv looks in /etc/service too (default).
            # But our service dir is $ROOT_DIR/service.
            # 
            # So, if we replace system 'sv', we must ensure it defaults to OUR directory.
            # This requires a wrapper script, not just a symlink to busybox.
            
            log_info "Creating sv wrapper script..."
            cat <<EOF > "$sys_sv"
#!/bin/sh
export SVDIR="$SV_ACTIVE"
exec "$BIN_DIR/sv" "\$@"
EOF
            chmod +x "$sys_sv"
            log_success "Created 'sv' wrapper at $sys_sv (defaults to $SV_ACTIVE)"
            ;;
        *) ;;
    esac

    log_success "Deployment complete."
}
