# Dockerfile (Arch Linux - bspwm GUI)
# Stage 1: Build and customize the rootfs for development
ARG TARGETPLATFORM
FROM ogarcia/archlinux AS customizer

# Copy custom scripts first
COPY scripts/download-firmware /usr/local/bin/

# Copy our bashrc script to the rootfs
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# Update base system and install everything in a single layer.
# The container never runs an X server of its own - Termux:X11 provides it over
# /tmp/.X11-unix - so only X client libraries and the tools the theme calls are needed.
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # Core utilities
    bash \
    dialog \
    coreutils \
    file \
    findutils \
    grep \
    sed \
    gawk \
    # diffutils: Essential on Debian, a separate package here - apply.sh needs cmp
    diffutils \
    curl \
    wget \
    ca-certificates \
    bash-completion \
    # systemd includes udev, networkd, resolved
    systemd \
    dbus \
    # Compression tools
    zip \
    unzip \
    7zip \
    bzip2 \
    xz \
    tar \
    gzip \
    # System tools
    htop \
    btop \
    vim \
    nano \
    micro \
    git \
    sudo \
    openssh \
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
    # Wireless networking tools for hotspot functionality
    iw \
    # Logging & Rotation
    logrotate \
    # Python (python-xlib and python-gobject drive the applets)
    python \
    python-pip \
    python-xlib \
    python-gobject \
    # Audio (libpulse ships pactl; the daemon lives on the Android side)
    libpulse \
    pavucontrol \
    # bspwm desktop and X stack
    bspwm \
    polybar \
    rofi \
    picom \
    dunst \
    feh \
    gsimplecal \
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
    xcursor-themes \
    at-spi2-core \
    tumbler \
    # Terminal and file manager (DE-agnostic; the theme renames them to Terminal/Files)
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
    # Icon themes, GTK and SVG helpers
    adwaita-icon-theme \
    adwaita-cursors \
    papirus-icon-theme \
    hicolor-icon-theme \
    gtk3 \
    gtk-update-icon-cache \
    librsvg \
    # Fonts (Symbols Nerd Font ships inside the theme, not via pacman)
    inter-font \
    noto-fonts \
    noto-fonts-emoji \
    ttf-jetbrains-mono \
    # Clipboard, notifications, user directories, permissions
    xclip \
    xsel \
    xdg-utils \
    xdg-user-dirs \
    libnotify \
    polkit \
    && pacman -Scc --noconfirm

# ============================================================
# Wire up the bspwm desktop: session launchers, autostart unit,
# icon/font caches, and the Catppuccin theme.
# ============================================================

# Install the bspwm session launchers and the autostart service
COPY scripts/bspwm/bspwm-start   /usr/local/bin/bspwm-start
COPY scripts/bspwm/bspwm-session /usr/local/bin/bspwm-session
RUN chmod +x /usr/local/bin/bspwm-start /usr/local/bin/bspwm-session

RUN cat > /etc/systemd/system/bspwm-autostart.service << 'EOF'
[Unit]
Description=bspwm touch desktop on Termux:X11 (Droidspaces)
After=graphical.target dbus.service systemd-logind.service
ConditionPathExists=/run/droidspaces/container.config

[Service]
Type=simple
User=root
# bspwm-start waits for the X server itself, so only the Termux:X11 flag is gated here.
ExecCondition=/bin/sh -c "grep -q 'enable_termux_x11=1' /run/droidspaces/container.config"
ExecStart=/usr/local/bin/bspwm-start
Restart=always
RestartSec=3
TimeoutStopSec=10

[Install]
WantedBy=graphical.target
EOF

RUN chmod 644 /etc/systemd/system/bspwm-autostart.service && \
    mkdir -p /etc/systemd/system/graphical.target.wants && \
    ln -sf /etc/systemd/system/bspwm-autostart.service /etc/systemd/system/graphical.target.wants/bspwm-autostart.service

# Update icon and font caches in a final setup layer
RUN gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Adwaita 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true && \
    fc-cache -fv

# Seed the bspwm touch theme so EVERY user gets it by default.
#   /usr/share/droidspaces/bspwm-theme  - read-only master copy (source for runtime seeding)
#   /root                               - the default desktop user (root)
#   /etc/skel                           - future users created with useradd -m
# gtk-4.0/wallpaper links are RELATIVE so they stay valid wherever the home ends up.
# Nerd fonts go system-wide so every user has the bar glyphs regardless of seeding.
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

# ============================================================
# Android / Droidspaces container compatibility fixes.
# ============================================================

# Configure legacy iptables (MANDATORY for Android compatibility)
RUN ln -sf /usr/bin/iptables-legacy /usr/bin/iptables && \
    ln -sf /usr/bin/ip6tables-legacy /usr/bin/ip6tables && \
    ln -sf /usr/bin/arptables-legacy /usr/bin/arptables && \
    ln -sf /usr/bin/ebtables-legacy /usr/bin/ebtables

# Configure locales, environment, SSH, and user directories
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    # Configure SSH (Disable Root Login)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Create default user directories
    xdg-user-dirs-update

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

# Arch doesn't have _apt user by default, but if some tool creates it:
grep -q '^_apt:' /etc/passwd && usermod -g aid_inet _apt || true

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
GUEST_SYSTEMD_PATH="/usr/lib/systemd/system"
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

# ============================================================
# GPU (custom Mesa for Adreno: freedreno + turnip).
# ============================================================

# Install custom mesa from lfdevs/mesa-for-android-container
COPY scripts/install-mesa /usr/local/bin/install-mesa
RUN chmod +x /usr/local/bin/install-mesa && install-mesa

# Final cleanup of the pacman cache
RUN pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# Stage 2: Export to scratch for extraction
FROM scratch AS export
LABEL droidspaces.name="Arch Linux - bspwm" \
      droidspaces.distro="Arch" \
      droidspaces.description="Arch Linux rootfs with the bspwm tiling window manager (touch-friendly Catppuccin desktop). Runs on Kernel 5.10 and above only." \
      droidspaces.author="Droidspaces developers"

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
