#!/bin/bash
# roytalk -- tune kernel and network settings for a small (1 GB) web VM.
#
#   sudo deploy/tune-sysctl.sh
#
# Idempotent: (re)writes /etc/sysctl.d/90-roytalk.conf and applies it. The
# swap stage of setup-server.sh writes vm.swappiness to the same file, so it
# appends instead of overwriting; running this script afterwards is safe.
set -euo pipefail

CONF=/etc/sysctl.d/90-roytalk.conf

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

cat > "$CONF" <<'EOF'
# roytalk: kernel/network tuning for a 1 GB VM running nginx + GNU Artanis.
# Applied by deploy/tune-sysctl.sh; remove that file to undo.

# --- accept queue and SYN backlog -----------------------------------------
# Artanis listens with server.backlog = 128; nginx queues to it. 1024 absorbs
# traffic bursts without changing the application.
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 1024
net.core.netdev_max_backlog = 1024

# --- connection churn ------------------------------------------------------
# Short-lived HTTP connections are the norm; recycle TIME_WAIT sockets and
# close idle keep-alives sooner than the 2 h default.
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_slow_start_after_idle = 0

# --- socket buffers --------------------------------------------------------
# Cap each direction at 4 MB: enough for a slow reader, small enough to leave
# memory for PostgreSQL and the app.
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304

# --- flood protection ------------------------------------------------------
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3

# --- file descriptors ------------------------------------------------------
fs.file-max = 131072

# --- memory and swap -------------------------------------------------------
# setup-server.sh creates a 2 GB swapfile; prefer RAM, and keep dentries and
# inodes cached a little longer than the default.
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

chmod 644 "$CONF"
sysctl --system >/dev/null

echo "Applied $CONF:"
sysctl -n net.core.somaxconn net.ipv4.tcp_max_syn_backlog \
          net.ipv4.tcp_tw_reuse fs.file-max vm.swappiness
