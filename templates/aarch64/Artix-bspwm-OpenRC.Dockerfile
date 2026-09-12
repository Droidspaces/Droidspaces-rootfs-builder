# syntax=docker/dockerfile:1.6
# Dockerfile (Artix Linux, OpenRC - bspwm GUI)
#
# Uses Armtix (ARM64 Artix) rootfs tarball for Android device compatibility.
# eudev supplies udev, while Artix's *-openrc packages supply service scripts.
#
# The desktop is identical to the Arch/Ubuntu bspwm templates; only the init glue
# differs. Two packages the others use do not exist in the Armtix repos:
#   gsimplecal   - the tap-the-clock calendar popup, so that button does nothing
#   xcursor-themes - costs the whiteglass/redglass/handhelds entries in Settings;
#                    adwaita-cursors (the default) is present
# Inter is not packaged here either, but the theme bundles it, so the font is fine.

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
    pacman --disable-sandbox -Rdd --noconfirm linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-aarch64-lts-headers mkinitcpio mkinitcpio-busybox linux-firmware linux-firmware-whence linux-firmware-amdgpu linux-firmware-atheros linux-firmware-broadcom linux-firmware-cirrus linux-firmware-intel linux-firmware-mediatek linux-firmware-nvidia linux-firmware-other linux-firmware-radeon linux-firmware-realtek 2>/dev/null || true && \
    pacman-key --populate artix && \
    pacman --disable-sandbox -Syu --noconfirm --ignore linux-aarch64,linux-aarch64-lts,linux-aarch64-headers,linux-aarch64-lts-headers,linux-firmware,linux-firmware-whence,mkinitcpio && \
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
        diffutils \
        zip \
        unzip \
        7zip \
        bzip2 \
        xz \
        tar \
        gzip \
        btop \
        micro \
        iw \
        elogind \
        elogind-openrc \
        avahi \
        avahi-openrc \
        python \
        python-pip \
        python-xlib \
        python-gobject \
        python-dbus \
        libpulse \
        pavucontrol \
        bspwm \
        polybar \
        rofi \
        picom \
        dunst \
        feh \
        xdotool \
        scrot \
        xorg-server \
        xorg-xinit \
        xorg-xdpyinfo \
        xorg-xrdb \
        xorg-xsetroot \
        xorg-xprop \
        xorg-xkill \
        xorg-xrandr \
        xorg-xauth \
        xorg-xhost \
        at-spi2-core \
        tumbler \
        xfce4-terminal \
        thunar \
        thunar-volman \
        thunar-archive-plugin \
        gvfs \
        gvfs-mtp \
        gvfs-gphoto2 \
        gvfs-smb \
        desktop-file-utils \
        shared-mime-info \
        adwaita-icon-theme \
        adwaita-cursors \
        papirus-icon-theme \
        hicolor-icon-theme \
        gtk3 \
        gtk-update-icon-cache \
        librsvg \
        noto-fonts \
        noto-fonts-emoji \
        ttf-jetbrains-mono \
        xclip \
        xsel \
        xdg-utils \
        xdg-user-dirs \
        libnotify \
        polkit && \
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
RUN sed -i '/en_US.UTF-8/s/^#\s\?//' /etc/locale.gen && \
    locale-gen && \
    printf '%s\n' 'LANG=en_US.UTF-8' > /etc/locale.conf && \
    install -d -m 0755 /run/sshd && \
    sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf && \
    userdel -r armtix 2>/dev/null || true

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

# Tell OpenRC it's in an LXC-style container (same as Alpine)
sed -i 's/^#\?rc_sys=.*/rc_sys="lxc"/' /etc/rc.conf

# Remove "dev" dependency from machine-id if it exists
if [ -f /etc/init.d/machine-id ]; then
    sed -i 's/need root dev/need root/' /etc/init.d/machine-id
fi

# Console getty. Artix boots with openrc-init (no inittab); gettys are
# agetty.<port> services. Drop the VT gettys (no VTs in a container) and add
# one on /dev/console for the Droidspaces foreground console. /etc/securetty
# already lists console, and PAM's login stack does not consult it anyway.
for n in 1 2 3 4 5 6; do rc-update del agetty.tty$n default; done
ln -sf agetty /etc/init.d/agetty.console
cp /etc/conf.d/agetty.tty1 /etc/conf.d/agetty.console
rc-update add agetty.console default

# dhcpcd ships enabled in the default runlevel. It must not start unconditionally
# (breaks cellular networking in host network mode); NetworkManager handles DHCP
# in NAT/gateway mode via the gated service below.
rc-update del dhcpcd default

# Let udev actually run under rc_sys="lxc": its script is excluded in every
# container type via "keyword -containers", and it needs sysfs, which is also
# container-excluded (Droidspaces mounts /sys before init, so the need is moot).
sed -i -e '/keyword -containers/d' -e 's/need sysfs dev-mount/need dev-mount/' /etc/init.d/udev

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
    # NetworkManager's script exits non-zero while "inactive" (started, not yet
    # online). The daemon is running either way, so don't fail this service on it.
    eend 0
}

stop() {
    is_managed_mode || return 0
    rc-service NetworkManager stop
}
EOT
chmod 0755 /etc/init.d/droidspaces-network

# /proc/sys is read-only in Droidspaces containers and Artix's sysctl.d defaults
# are meaningless on an Android kernel; drop the service so it stops erroring at boot.
rc-update del sysctl boot

# bspwm touch desktop. The systemd templates use a unit with ExecCondition +
# Restart=always; the OpenRC equivalent is a conditional start() (same shape as
# droidspaces-network above, returning 0 so a non-X11 container is not a failure)
# driving supervise-daemon, which supplies the respawn.
cat > /etc/init.d/bspwm-autostart <<'EOT'
#!/sbin/openrc-run

description="bspwm touch desktop on Termux:X11 (Droidspaces)"
pidfile="/run/bspwm-autostart.pid"

depend() {
    need dbus
    after udev droidspaces-udev-trigger elogind
}

x11_enabled() {
    grep -qs 'enable_termux_x11=1' /run/droidspaces/container.config
}

start() {
    if ! x11_enabled; then
        einfo "Termux:X11 not enabled for this container; desktop not started"
        return 0
    fi
    ebegin "Starting bspwm touch desktop"
    # bspwm-start waits for the X server itself, so it is fine to launch before
    # Termux:X11 is open; supervise-daemon restarts the session if it exits.
    supervise-daemon bspwm-autostart --start \
        --pidfile "$pidfile" --respawn-delay 3 \
        /usr/local/bin/bspwm-start
    eend $?
}

stop() {
    x11_enabled || return 0
    ebegin "Stopping bspwm touch desktop"
    supervise-daemon bspwm-autostart --stop --pidfile "$pidfile"
    eend $?
}
EOT
chmod 0755 /etc/init.d/bspwm-autostart

# OpenRC service enablement.
rc-update add udev sysinit
rc-update del udev-trigger sysinit 2>/dev/null || true
rc-update add droidspaces-udev-trigger sysinit
rc-update add dbus default
rc-update add droidspaces-network default
rc-update add sshd default
# elogind provides the seat/session tracking polkit expects; avahi matches the
# Arch template, where the Zeroconf launchers in the app menu need the daemon.
[ -f /etc/init.d/elogind ] && rc-update add elogind boot
[ -f /etc/init.d/avahi-daemon ] && rc-update add avahi-daemon default
rc-update add bspwm-autostart default

# Keep logs bounded on storage-constrained Android devices.
if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    grep -q '^maxsize 50M$' /etc/logrotate.conf || echo 'maxsize 50M' >> /etc/logrotate.conf
fi

printf 'Post-extraction OpenRC fixes applied on %s\n' "$(date)" > /etc/droidspaces
EOF_RUN

# ============================================================
# Wire up the bspwm desktop: session launchers, icon/font caches,
# and the Catppuccin theme. Identical to the Arch/Ubuntu templates.
# ============================================================

COPY scripts/download-firmware /usr/local/bin/
COPY scripts/bspwm/bspwm-start   /usr/local/bin/bspwm-start
COPY scripts/bspwm/bspwm-session /usr/local/bin/bspwm-session
RUN chmod +x /usr/local/bin/download-firmware /usr/local/bin/bspwm-start /usr/local/bin/bspwm-session

RUN gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Adwaita 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true && \
    fc-cache -fv

# Seed the bspwm touch theme so EVERY user gets it by default.
#   /usr/share/droidspaces/bspwm-theme  - read-only master copy (runtime seeding source)
#   /root                               - the default desktop user (root)
#   /etc/skel                           - future users created with useradd -m
# gtk-4.0/wallpaper links are RELATIVE so they stay valid wherever the home ends up.
# Inter and the Nerd Font go system-wide so the bar glyphs and UI font are present
# regardless of seeding - neither is packaged in the Armtix repos.
COPY scripts/bspwm/bspwm-theme /usr/share/droidspaces/bspwm-theme

RUN set -eu; \
    THEME=catppuccin-mocha-lavender-standard+default; \
    mkdir -p /usr/local/share/fonts; \
    cp -a /usr/share/droidspaces/bspwm-theme/fonts/. /usr/local/share/fonts/; \
    fc-cache -f >/dev/null 2>&1 || true; \
    for home in /root /etc/skel; do \
        mkdir -p "$home"; \
        cp -a /usr/share/droidspaces/bspwm-theme/payload/. "$home/"; \
        mkdir -p "$home/.config/gtk-4.0"; \
        for f in gtk.css gtk-dark.css assets; do \
            ln -sfn "../../.themes/$THEME/gtk-4.0/$f" "$home/.config/gtk-4.0/$f"; \
        done; \
        ln -sfn "../../Pictures/wallpapers/evening-sky.png" "$home/.config/bspwm/wallpaper"; \
        chmod +x "$home"/.config/bspwm/*.sh "$home"/.config/bspwm/*.py \
                 "$home"/.config/polybar/launch.sh "$home"/start-desktop.sh 2>/dev/null || true; \
        chmod -x "$home"/.config/bspwm/autostart.d/* 2>/dev/null || true; \
        [ -f "$home/.config/Thunar/uca.xml" ] && \
            sed -i "s#<unique-id>PLACEHOLDER</unique-id>#<unique-id>1000000000-1</unique-id>#" "$home/.config/Thunar/uca.xml" || true; \
    done; \
    chown -R root:root /root/.config /root/.themes /root/.local /root/Pictures /root/start-desktop.sh

# Create the default user directories the theme's Files/wallpaper paths expect.
RUN xdg-user-dirs-update || true

# ============================================================
# GPU (custom Mesa for Adreno: freedreno + turnip).
# ============================================================

# Artix ships Arch's packages, so install-mesa's archlinux path applies unchanged.
COPY scripts/install-mesa /usr/local/bin/install-mesa
RUN chmod +x /usr/local/bin/install-mesa && install-mesa

# Final package-cache cleanup.
RUN pacman --disable-sandbox -Scc --noconfirm && rm -rf /var/cache/pacman/pkg/*

# Export a plain rootfs for DroidSpaces extraction.
FROM scratch AS export
LABEL droidspaces.name="Artix Linux - bspwm" \
      droidspaces.distro="Artix" \
      droidspaces.description="Artix Linux (Armtix) rootfs with the bspwm tiling window manager (touch-friendly Catppuccin desktop). Uses OpenRC." \
      droidspaces.author="Droidspaces developers"
COPY --from=customizer / /
