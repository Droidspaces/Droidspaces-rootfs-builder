# Dockerfile (Minimal)
# Stage 1: Build and customize the rootfs for development (Minimal - Debian 13)
ARG TARGETPLATFORM
FROM debian:trixie AS customizer

ENV DEBIAN_FRONTEND=noninteractive

# Update base system and enable non-free/contrib
RUN (sed -i 's/main/main contrib non-free/g' /etc/apt/sources.list 2>/dev/null || sed -i 's/Components: main/Components: main contrib non-free/g' /etc/apt/sources.list.d/debian.sources) && \
    apt-get update && apt-get upgrade -y

# Copy custom scripts first
COPY scripts/download-firmware /usr/local/bin/

# Copy our bashrc script to the rootfs
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# Install Minimal package set
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Core utilities
    bash \
    dialog \
    coreutils \
    file \
    findutils \
    grep \
    sed \
    gawk \
    curl \
    wget \
    ca-certificates \
    locales \
    bash-completion \
    udev \
    dbus \
    systemd-sysv \
    systemd-resolved \
    # Basic tools requested by user
    git \
    nano \
    sudo \
    # Networking & SSH
    openssh-server \
    net-tools \
    iptables \
    iputils-ping \
    iproute2 \
    dnsutils \
    # Procps for system monitoring
    procps \
    # Essential kernel module support
    kmod \
    && apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure iptables-legacy (MANDATORY for Android compatibility)
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Configure locales, environment, SSH, and user setup
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    # Configure SSH (Disable Root Login)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Remove default user if it exists
    deluser --remove-home debian || true

# Fix DHCP in the container
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# Apply Android compatibility fixes (Systemd and Udev)
RUN <<EOF_RUN

# --- 1. General Fixes ---
# Android network group setup (required for socket access on Android kernels)
grep -q '^aid_inet:' /etc/group    || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# Root permissions for Android hardware access
usermod -a -G aid_inet,aid_net_raw,input,video,tty root || true

# _apt needs aid_inet as primary group so apt works on Android
grep -q '^_apt:' /etc/passwd && usermod -g aid_inet _apt || true

# Future users created with adduser automatically get network access
if [ -f /etc/adduser.conf ]; then
    sed -i '/^EXTRA_GROUPS=/d; /^ADD_EXTRA_GROUPS=/d' /etc/adduser.conf
    echo 'ADD_EXTRA_GROUPS=1' >> /etc/adduser.conf
    echo 'EXTRA_GROUPS="aid_inet aid_net_raw input video tty"' >> /etc/adduser.conf
fi

# --- 2. Systemd-Specific Fixes ---
# Mask problematic services for Android kernels
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

# Journald configuration (skip Audit, KMsg, etc)
cat >> /etc/systemd/journald.conf << 'EOT'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ds-logging.conf << 'EOT'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

# Enable essential services
mkdir -p /etc/systemd/system/multi-user.target.wants
GUEST_SYSTEMD_PATH="/lib/systemd/system"
for service in dbus.service systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
        ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
    fi
done

# Disable power button handling in systemd-logind
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

# Apply udev overrides
# 1. Trigger override (Prevents coldplugging Android hardware)
mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

# 2. Read-only path overrides to prevent failures
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

# Limit specific network services to only start in NAT mode
# Prevents cellular network breakage when running in host network mode
for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
EOF
    fi
done

# Configure logrotate for Android
if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi

# Mark fixes as completed
echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

# Copy binfmt scripts
COPY scripts/binfmt/qemu-binfmt-register.sh /usr/local/bin/
COPY scripts/binfmt/qemu-binfmt-register.service /etc/systemd/system/
RUN chmod +x /usr/local/bin/qemu-binfmt-register.sh && \
    chmod 644 /etc/systemd/system/qemu-binfmt-register.service && \
    ln -sf /etc/systemd/system/qemu-binfmt-register.service /etc/systemd/system/multi-user.target.wants/qemu-binfmt-register.service

# Purge and reinstall qemu and binfmt in the exact order specified
RUN apt-get purge -y qemu-* binfmt-support || true && \
    apt-get autoremove -y && \
    apt-get autoclean && \
    # Remove any leftover config files
    rm -rf /var/lib/binfmts/* && \
    rm -rf /etc/binfmt.d/* && \
    rm -rf /usr/lib/binfmt.d/qemu-* && \
    # Update package lists
    apt-get update && \
    # Install ONLY these packages (in this specific order)
    apt-get install -y qemu-user-static && \
    apt-get install -y binfmt-support && \
    # Add amd64 architecture and install libc6:amd64
    dpkg --add-architecture amd64 && \
    apt-get update && \
    apt-get install -y libc6:amd64

# Final cleanup of APT cache
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Export to scratch for extraction
FROM scratch AS export

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
