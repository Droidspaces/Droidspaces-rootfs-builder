# AzureLinux-3.0-base.Dockerfile
# Stage 1: Build and customize Azure Linux 3.0 rootfs for Droidspaces.

ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM mcr.microsoft.com/azurelinux/base/core:3.0 AS customizer

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install packages.
RUN tdnf -y update && \
    tdnf -y install \
      systemd \
      systemd-udev \
      systemd-resolved \
      shadow-utils \
      iproute \
      iputils \
      curl \
      wget \
      ca-certificates \
      git \
      openssh-server \
      net-tools \
      iptables \
      bind-utils \
      procps-ng \
      bash \
      dialog \
      file \
      glibc-locales-all \
      bash-completion \
      findutils \
      coreutils \
      grep \
      sed \
      nano \
      sudo \
      dbus \
      kmod \
      tar \
      gzip \
      bzip2 \
      xz \
      util-linux \
      gawk \
      which && \
    tdnf clean all

# Droidspaces NAT DHCP profile.
RUN mkdir -p /etc/systemd/network && \
    cat > /etc/systemd/network/20-eth0.network <<'EOF'
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

# Droidspaces / Android compatibility fixes.
RUN <<'EOF_RUN'
set -e

# Android network groups.
grep -q '^aid_inet:' /etc/group || echo 'aid_inet:x:3003:' >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# Root permissions for Android hardware/network access.
usermod -a -G aid_inet,aid_net_raw,input,video,tty root || true

# Azure/RPM-family package-manager user adjustment, if such a user exists.
grep -q '^_tdnf:' /etc/passwd && usermod -g aid_inet _tdnf || true

# Prefer iptables-legacy if available.
if command -v update-alternatives >/dev/null 2>&1 && [ -x /usr/sbin/iptables-legacy ]; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy || true
fi

# Mask problematic services for Android kernels.
mkdir -p /etc/systemd/system
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

# Nuke useless iptables service
rm -f /etc/systemd/system/iptables.service \
      /etc/systemd/scripts/iptables \
      /etc/systemd/scripts/iptables.stop \
      /etc/systemd/system/multi-user.target.wants/iptables.service || true

# Journald configuration.
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/droidspaces.conf <<'EOF'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOF

# Find systemd unit directory.
if [ -d /usr/lib/systemd/system ]; then
    GUEST_SYSTEMD_PATH=/usr/lib/systemd/system
else
    GUEST_SYSTEMD_PATH=/lib/systemd/system
fi

# Enable essential services only if present.
mkdir -p /etc/systemd/system/multi-user.target.wants
for service in dbus.service systemd-udevd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
        ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
    fi
done

# Disable power-button behavior.
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf <<'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

# Restrict udev trigger to less dangerous subsystems.
mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

# Remove read-write path conditions that fail in Droidspaces.
for unit in \
    systemd-udevd.service \
    systemd-udev-trigger.service \
    systemd-udev-settle.service \
    systemd-udevd-kernel.socket \
    systemd-udevd-control.socket
do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

# Limit network daemons to Droidspaces NAT mode.
for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -e "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" <<'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
EOF
    fi
done

echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

# Final cleanup.
RUN rm -rf /var/cache/tdnf /var/lib/tdnf /tmp/* /var/tmp/* || true

# Stage 2: Export to scratch for extraction.
FROM scratch AS export
COPY --from=customizer / /
