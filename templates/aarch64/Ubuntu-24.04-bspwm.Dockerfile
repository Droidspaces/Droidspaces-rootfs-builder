# Dockerfile (GUI)
# Stage 1: Build and customize the rootfs for development
ARG TARGETPLATFORM
FROM ubuntu:24.04 AS customizer

ENV DEBIAN_FRONTEND=noninteractive

# Update base system
RUN apt-get update && apt-get upgrade -y

# Copy custom scripts first
COPY scripts/download-firmware /usr/local/bin/

# Copy our bashrc script to the rootfs
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# This is the main installation layer. All package installations, PPA additions,
# and setup are done here to minimize layers and maximize build speed.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Essentials for adding PPAs
    software-properties-common \
    gnupg \
    # Add PPAs for fastfetch and Firefox ESR
    && add-apt-repository ppa:zhangsongcui3371/fastfetch -y && \
    add-apt-repository ppa:mozillateam/ppa -y && \
    printf 'Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' > /etc/apt/preferences.d/mozillateam && \
    # Update package lists again after adding PPAs
    apt-get update && \
    # Install all packages in a single command
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
    # Compression tools
    zip \
    unzip \
    p7zip-full \
    bzip2 \
    xz-utils \
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
    openssh-server \
    net-tools \
    iptables \
    iputils-ping \
    iproute2 \
    dnsutils \
    usbutils \
    pciutils \
    lsof \
    psmisc \
    procps \
    fastfetch \
    kmod \
    # Wireless networking tools for hotspot functionality
    iw \
    # Logging & Rotation
    logrotate \
    # Python Development
    python3 \
    python3-pip \
    python3-venv \
    # Audio
    pulseaudio \
    pulseaudio-utils \
    pavucontrol \
    # bspwm desktop and X stack
    bspwm \
    polybar \
    rofi \
    picom \
    dunst \
    feh \
    hsetroot \
    gsimplecal \
    xdotool \
    scrot \
    xinit \
    xorg \
    dbus-x11 \
    at-spi2-core \
    xcursor-themes \
    tumbler \
    # Terminal and file manager (DE-agnostic; the theme renames them to Terminal/Files)
    xfce4-terminal \
    thunar \
    thunar-volman \
    thunar-archive-plugin \
    gvfs \
    gvfs-backends \
    gvfs-fuse \
    # Icon themes
    adwaita-icon-theme-full \
    hicolor-icon-theme \
    papirus-icon-theme \
    # GTK theme engines and SVG/GTK helpers
    librsvg2-common \
    libgtk-3-bin \
    # Fonts (Inter and Symbols Nerd Font ship inside the theme, not via apt)
    fonts-noto-core \
    fonts-noto-ui-core \
    fonts-noto-color-emoji \
    fonts-jetbrains-mono \
    # X utilities, clipboard, notifications
    x11-xserver-utils \
    x11-utils \
    xclip \
    xsel \
    xdg-utils \
    libnotify-bin \
    # Python bits for the applets (edge-resize, volume slider, icon cache)
    python3-xlib \
    python3-gi \
    gir1.2-gtk-3.0 \
    # User directory management
    xdg-user-dirs \
    # Browser (Firefox ESR from PPA)
    firefox-esr \
    # PolicyKit for permissions
    policykit-1 \
    && apt-get purge -y gdm3 gnome-session gnome-shell whoopsie && \
    apt-get autoremove -y

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
#   /etc/skel                           - future users created with adduser
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

# Let a non-root desktop user power the container off from the bspwm power menu.
# Scoped to exactly those two commands - not blanket sudo - and to the %sudo group,
# which is empty until an admin adds someone, so this grants nothing on its own.
# Without it the power menu prompts for a password and then fails, because
# `usermod -aG sudo <user>` alone does not grant sudo.
RUN printf '%%sudo ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot\n' \
      > /etc/sudoers.d/10-droidspaces-power && \
    chmod 440 /etc/sudoers.d/10-droidspaces-power && \
    visudo -c -f /etc/sudoers.d/10-droidspaces-power

# Configure iptables-legacy (Required for Android compatibility)
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Configure locales, environment, SSH, and user setup in a single layer
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    # Configure SSH (Disable Root Login)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Create default user directories
    xdg-user-dirs-update && \
    # Remove default ubuntu user if it exists
    deluser --remove-home ubuntu || true

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

# ============================================================
# Multi-arch support (amd64 translation) and GPU (Mesa).
# ============================================================

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
    sed -i '/^Types: deb$/a Architectures: arm64 armhf' /etc/apt/sources.list.d/ubuntu.sources && \
    echo "" >> /etc/apt/sources.list.d/ubuntu.sources && \
    echo "Types: deb" >> /etc/apt/sources.list.d/ubuntu.sources && \
    echo "URIs: http://archive.ubuntu.com/ubuntu/" >> /etc/apt/sources.list.d/ubuntu.sources && \
    echo "Suites: noble noble-updates noble-security" >> /etc/apt/sources.list.d/ubuntu.sources && \
    echo "Components: main universe restricted multiverse" >> /etc/apt/sources.list.d/ubuntu.sources && \
    echo "Architectures: amd64" >> /etc/apt/sources.list.d/ubuntu.sources && \
    echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" >> /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && \
    apt-get install -y libc6:amd64

# Install custom mesa from lfdevs/mesa-for-android-container
COPY scripts/install-mesa /usr/local/bin/install-mesa
RUN chmod +x /usr/local/bin/install-mesa && install-mesa

# Final cleanup of APT cache
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Export to scratch for extraction
FROM scratch AS export
LABEL droidspaces.name="Ubuntu 24.04.04 LTS - bspwm" \
      droidspaces.distro="Ubuntu" \
      droidspaces.description="Ubuntu 24.04 rootfs with basic packages and the bspwm tiling window manager (touch-friendly Catppuccin desktop)." \
      droidspaces.author="Droidspaces developers"

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
