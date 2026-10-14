# KDE Plasma on the phone's own Mali GPU, through libhybris and Mesa Zink, shown with Anland.
# Needs a stock Mali driver and the kbase pid namespace fix in the kernel, see
# https://github.com/ravindu644/Droidspaces-Mali
FROM fedora:44 AS customizer

ARG MALI_RELEASE=https://api.github.com/repos/ravindu644/Droidspaces-Mali/releases/tags/fedora-44

COPY scripts/download-firmware /usr/local/bin/
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# Fedora's own KWin rebuilt with Anland's backend, Mesa 25.1 with Zink for apps, and
# libhybris with the session
RUN dnf -y install jq && \
    mkdir -p /tmp/mali && cd /tmp/mali && \
    curl -fsSL "$MALI_RELEASE" | jq -r '.assets[].browser_download_url' | xargs -n1 curl -fsSLO && \
    ls /tmp/mali/*.rpm

# systemd-pam is only a weak dependency, and without pam_systemd the session gets no
# logind session and no /run/user
RUN dnf -y install --setopt=install_weak_deps=False \
    bash-completion coreutils curl file findutils gawk grep sed tar xz zip unzip \
    dbus-daemon systemd systemd-pam systemd-udev systemd-networkd systemd-resolved \
    sudo passwd nano git htop fastfetch procps-ng psmisc lsof kmod usbutils pciutils \
    openssh-server iproute iputils bind-utils net-tools iptables-legacy logrotate \
    glibc-langpack-en \
    plasma-desktop plasma-pa plasma-milou kinfocenter kscreen konsole dolphin kate ark xdg-desktop-portal-kde \
    pipewire pipewire-alsa pipewire-pulseaudio wireplumber \
    glx-utils egl-utils vulkan-tools \
    /tmp/mali/droidspaces-mali-*.rpm && \
    # Only the KWin packages Plasma pulled in, the rest of the set stays out
    dnf -y upgrade /tmp/mali/kwin*.rpm && \
    # The apt-mark hold of dnf: Fedora's next KWin would drop Anland's backend
    dnf versionlock add $(rpm -qp --qf '%{name}\n' /tmp/mali/*.rpm | sort -u | xargs rpm -q --qf '%{name}\n' 2>/dev/null | grep -v 'not installed') && \
    dnf clean all && rm -rf /tmp/mali /var/cache/dnf/*

# iptables-legacy is mandatory on Android kernels
RUN alternatives --set iptables /usr/sbin/iptables-legacy && \
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Plasma's whole session runs inside plasma-mali@.service, not as systemd user units
    printf '[General]\nsystemdBoot=false\n' > /etc/xdg/startkderc

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

RUN <<EOF_RUN
grep -q '^aid_inet:' /etc/group    || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group
usermod -a -G aid_inet,aid_net_raw,input,video,tty root || true

# Droidspaces chowns the GPU nodes to this GID at start, and adds the group itself only
# when it's missing, which is too late for users created here
getent group droidspaces-gpu >/dev/null || groupadd -r -g 786 droidspaces-gpu
# Every new user gets network, hardware and GPU access, like adduser's EXTRA_GROUPS on Debian
sed -i '/^GROUPS=/d' /etc/default/useradd
echo 'GROUPS=aid_inet,aid_net_raw,input,video,tty,audio,render,droidspaces-gpu' >> /etc/default/useradd

# The desktop user, fedora / 1234, with Plasma starting on every container start
useradd -m -G wheel,aid_inet,aid_net_raw,input,video,tty,audio,render,droidspaces-gpu fedora
echo 'fedora:1234' | chpasswd
systemctl enable plasma-mali@fedora

ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

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

mkdir -p /etc/systemd/system/multi-user.target.wants
for service in dbus.service systemd-udevd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "/usr/lib/systemd/system/$service" ]; then
        ln -sf "/usr/lib/systemd/system/$service" "/etc/systemd/system/multi-user.target.wants/$service"
    fi
done

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOT'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOT

# Don't coldplug Android's hardware
mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOT'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOT

for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

# Host and none network modes have no network of their own to configure
for unit in systemd-resolved.service systemd-networkd.service; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOT'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -q '^net_mode=' /run/droidspaces/container.config && ! grep -qE '^net_mode=(host|none)$' /run/droidspaces/container.config"
EOT
done

sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
grep -q "maxsize 50M" /etc/logrotate.conf || echo "maxsize 50M" >> /etc/logrotate.conf

echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

# The app reads this to prefill the install wizard: GPU access, the Android partitions the
# Mali driver lives on, and sandboxing for Plasma's services. Anland stays off until its app
# is installed. build.sh moves it to the front of the tarball, where the app looks for it.
COPY scripts/mali/container.config /container.config

FROM scratch AS export
LABEL droidspaces.name="Fedora 44 - KDE Plasma on the Mali GPU" \
      droidspaces.distro="Fedora" \
      droidspaces.description="KDE Plasma on the phone's own Mali GPU through libhybris and Mesa Zink, shown with Anland. Needs a stock Mali driver and a kernel with the kbase pid namespace fix, see github.com/ravindu644/Droidspaces-Mali. User fedora, password 1234." \
      droidspaces.author="Droidspaces developers"
COPY --from=customizer / /
