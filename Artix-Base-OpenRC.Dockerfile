# syntax=docker/dockerfile:1.6
# Dockerfile (Artix Linux Base, OpenRC)
#
# Uses Armtix (ARM64 Artix) rootfs tarball for Android device compatibility.
# eudev supplies udev, while Artix's *-openrc packages supply service scripts.

# Download and prepare the Armtix rootfs
FROM alpine:latest AS bootstrap
RUN apk add --no-cache curl xz
WORKDIR /rootfs
RUN curl -fsSL https://armtixlinux.org/images/armtix-openrc-20260124.tar.xz | xz -d | tar x && \
    ln -sf usr/bin bin && \
    ln -sf usr/lib lib && \
    ln -sf usr/lib64 lib64 2>/dev/null || true && \
    ln -sf usr/sbin sbin

FROM scratch AS base
COPY --from=bootstrap /rootfs /

FROM base AS customizer

# Initialize pacman keyring and install the full development rootfs.
# NetworkManager is enabled through a DroidSpaces wrapper below so it only runs
# for NAT/gateway containers and cannot disturb Android host networking.
RUN pacman-key --init && \
    pacman-key --populate artix && \
    pacman --disable-sandbox -Syu --noconfirm && \
    pacman --disable-sandbox -S --needed --noconfirm \
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
        bash-completion \
        openrc \
        eudev \
        eudev-openrc \
        dbus \
        dbus-openrc \
        htop \
        vim \
        nano \
        git \
        sudo \
        openssh \
        openssh-openrc \
        networkmanager \
        networkmanager-openrc \
        net-tools \
        iptables \
        iputils \
        iproute2 \
        bind \
        usbutils \
        pciutils \
        lsof \
        psmisc \
        procps-ng \
        fastfetch \
        kmod \
        logrotate \
        base-devel \
        cmake \
        clang \
        llvm \
        valgrind \
        strace \
        ltrace \
        python \
        python-pip \
        docker \
        docker-openrc \
        docker-compose && \
    pacman --disable-sandbox -Scc --noconfirm

# Copy shell aliases into the rootfs.
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
RUN chmod 0755 /etc/profile.d/ds-aliases.sh

# Force the xtables legacy frontends required by Android networking.
RUN ln -sf /usr/bin/iptables-legacy /usr/bin/iptables && \
    ln -sf /usr/bin/ip6tables-legacy /usr/bin/ip6tables && \
    ln -sf /usr/bin/arptables-legacy /usr/bin/arptables && \
    ln -sf /usr/bin/ebtables-legacy /usr/bin/ebtables

# Configure locale and SSH. OpenRC's sshd service creates/uses the runtime state
# when booted, but keep the directory for container runtimes that start it early.
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen && \
    printf '%s\n' 'LANG=en_US.UTF-8' > /etc/locale.conf && \
    install -d -m 0755 /run/sshd && \
    sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# NetworkManager DHCP profile for eth* interfaces used by DroidSpaces.
RUN install -d -m 0700 /etc/NetworkManager/system-connections && \
    cat > /etc/NetworkManager/system-connections/droidspaces-ethernet.nmconnection <<'EOF'
[connection]
id=droidspaces-ethernet
type=ethernet
autoconnect=true

[match]
interface-name=eth*

[ipv4]
method=auto
route-metric=100

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF

# Apply Android compatibility fixes and install OpenRC-native services.
RUN <<'EOF_RUN'
set -eu

# Android network groups are required for socket access on Android kernels.
grep -q '^aid_inet:' /etc/group || echo 'aid_inet:x:3003:' >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# Permit root to access Android networking and exposed hardware devices.
usermod -a -G aid_inet,aid_net_raw,input,video,tty root || true

# Artix does not normally have _apt, but preserve compatibility if it is added.
if grep -q '^_apt:' /etc/passwd; then
    usermod -g aid_inet _apt
fi

# Restricted OpenRC coldplug service for container-safe udev triggers.
cat > /etc/init.d/droidspaces-udev-trigger <<'EOT'
#!/sbin/openrc-run

description="Restricted eudev coldplug for DroidSpaces"

depend() {
    need udev
    before localmount
    keyword -lxc -vserver
}

start() {
    ebegin "Triggering container-safe eudev subsystems"
    udevadm trigger --type=subsystems --action=add \
        --subsystem-match=usb \
        --subsystem-match=block \
        --subsystem-match=input \
        --subsystem-match=tty \
        --subsystem-match=net
    udevadm trigger --type=devices --action=add \
        --subsystem-match=usb \
        --subsystem-match=block \
        --subsystem-match=input \
        --subsystem-match=tty \
        --subsystem-match=net
    eend $?
}
EOT
chmod 0755 /etc/init.d/droidspaces-udev-trigger

# Conditional NetworkManager startup for NAT/gateway mode only.
cat > /etc/init.d/droidspaces-network <<'EOT'
#!/sbin/openrc-run

description="Conditional DroidSpaces NetworkManager startup"

depend() {
    need dbus
    after udev droidspaces-udev-trigger
}

is_managed_mode() {
    grep -qsE '(^|[[:space:]])net_mode=(nat|gateway)($|[[:space:]])' \
        /run/droidspaces/container.config
}

start() {
    if ! is_managed_mode; then
        einfo "Host networking detected; leaving Android networking untouched"
        return 0
    fi

    ebegin "Starting NetworkManager for DroidSpaces NAT/gateway mode"
    rc-service NetworkManager start
    eend $?
}

stop() {
    if rc-service NetworkManager status >/dev/null 2>&1; then
        ebegin "Stopping NetworkManager"
        rc-service NetworkManager stop
        eend $?
    fi
}
EOT
chmod 0755 /etc/init.d/droidspaces-network

# OpenRC service enablement.
rc-update add udev sysinit
rc-update del udev-trigger sysinit 2>/dev/null || true
rc-update add droidspaces-udev-trigger sysinit
rc-update add dbus default
rc-update add droidspaces-network default
rc-update add sshd default
rc-update add docker default

# Keep logs bounded on storage-constrained Android devices.
if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    grep -q '^maxsize 50M$' /etc/logrotate.conf || echo 'maxsize 50M' >> /etc/logrotate.conf
fi

printf 'Post-extraction OpenRC fixes applied on %s\n' "$(date)" > /etc/droidspaces
EOF_RUN

# Final package-cache cleanup.
RUN pacman --disable-sandbox -Scc --noconfirm && rm -rf /var/cache/pacman/pkg/*

# Export a plain rootfs for DroidSpaces extraction.
FROM scratch AS export
COPY --from=customizer / /
