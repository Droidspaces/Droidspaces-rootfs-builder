# Dockerfile (Alpine Linux Minimal)
# Stage 1: Build and customize the rootfs for development (Minimal - Alpine Linux)
ARG TARGETPLATFORM
FROM alpine:3.23 AS customizer

# Install key packages
RUN apk update && apk upgrade && \
    apk add \
    # Core utilities
    bash \
    coreutils \
    file \
    findutils \
    grep \
    sed \
    gawk \
    curl \
    wget \
    ca-certificates \
    tzdata \
    bash-completion \
    shadow \
    sudo \
    # Networking & SSH
    openssh \
    net-tools \
    iptables-legacy \
    iputils \
    iproute2 \
    # System monitoring
    procps \
    htop \
    # DHCP client + openrc
    dhcpcd \
    openrc \
    busybox-extras \
    && rm -rf /var/cache/apk/*

# Copy custom scripts
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /etc/profile.d/ds-aliases.sh

# Configure environment
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Apply Android compatibility fixes
RUN <<EOF_RUN
# --- 1. General Fixes ---
# Android network group setup (required for socket access on Android kernels)
grep -q '^aid_inet:' /etc/group    || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# Root permissions for Android hardware access
usermod -a -G aid_inet,aid_net_raw,input,video,tty root || true

# Configure legacy iptables (MANDATORY for Android compatibility)
ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables && \
ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables && \
ln -sf /usr/sbin/arptables-legacy /usr/sbin/arptables && \
ln -sf /usr/sbin/ebtables-legacy /usr/sbin/ebtables

# Tell OpenRC it's in an LXC-style container.
# This suppresses the hwdrivers/machine-id "needs dev" warnings without
# disabling anything useful. In hw-access mode, devtmpfs/sys are mounted
# by Droidspaces before init runs, so OpenRC never tries to manage them
# anyway - rc_sys="lxc" just stops it from complaining about their absence.
sed -i 's/^#\?rc_sys=.*/rc_sys="lxc"/' /etc/rc.conf

# Remove "dev" dependency from machine-id init script to prevent boot warnings
if [ -f /etc/init.d/machine-id ]; then
    sed -i 's/need root dev/need root/' /etc/init.d/machine-id
fi

# Fix inittab:
# 1. Remove useless tty1-6 (no VTs in a container)
# 2. Add console getty for the Droidspaces foreground console
# 3. Add console to securetty so root login is allowed
sed -i '/^tty[1-6]::/d' /etc/inittab
grep -q 'console::respawn' /etc/inittab || \
    echo 'console::respawn:/sbin/getty 38400 console' >> /etc/inittab
grep -q '^console$' /etc/securetty || echo 'console' >> /etc/securetty

# Wire up dhcpcd to the default runlevel by creating the symlink manually
# (rc-update can't run inside a Dockerfile build - no /run/openrc yet)
mkdir -p /etc/runlevels/default
ln -sf /etc/init.d/dhcpcd /etc/runlevels/default/dhcpcd

# Same for sshd if we want it on boot
ln -sf /etc/init.d/sshd /etc/runlevels/default/sshd

# Replace dhcpcd init script to only start in NAT network mode
# This is the OpenRC equivalent of systemd's ExecCondition - if the container
# is running in host network mode, dhcpcd is cleanly skipped at boot to prevent
# cellular network breakage and kernel panics on Android interfaces.
cat > /etc/init.d/dhcpcd << 'INITEOF'
#!/sbin/openrc-run

description="DHCP Client Daemon"

command="/sbin/dhcpcd"
command_args="-q -B ${command_args:-}"
command_background="true"
pidfile="/run/dhcpcd/pid"

depend() {
	provide net
	need localmount
	use logger network
	after bootmisc modules
	before dns
}

start_pre() {
	# Only start in NAT mode - prevents cellular network breakage in host network mode
	if ! grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config 2>/dev/null; then
		einfo "Skipping dhcpcd: not in NAT network mode"
		return 1
	fi
	checkpath -d /run/dhcpcd
}
INITEOF
chmod +x /etc/init.d/dhcpcd

# Additionally whitelist only container veth interfaces (eth*) in dhcpcd.conf
# as defense-in-depth against Android-internal interfaces (rmnet*, dit*, epdg*, etc.)
if [ -f /etc/dhcpcd.conf ]; then
    echo "allowinterfaces eth*" >> /etc/dhcpcd.conf
fi

# Mark fixes as completed
echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

# Final cleanup
RUN rm -rf /var/cache/apk/*

# Stage 2: Export to scratch for extraction
FROM scratch AS export

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
