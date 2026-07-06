# OpenWrt 24.10 minimal rootfs for VirtualAP container mode (Droidspaces NAT).
# Android kernels lack nf_tables, so this drops fw4/nftables for iptables-legacy
# + fw3 (the stack VirtualAP's provision_openwrt() expects).

ARG OPENWRT_VERSION=24.10.7

# Stage 1: official ARM64 rootfs as a file source (non-standard platform tag, no RUN here)
FROM --platform=linux/aarch64_generic openwrt/rootfs:armsr-armv8-${OPENWRT_VERSION} AS owrt

# Stage 2: customize on scratch (=build arch) so opkg below runs aarch64 binaries under QEMU
FROM scratch AS customizer
COPY --from=owrt / /

RUN <<EOF_RUN
set -e
mkdir -p /var/lock /var/run /tmp
opkg update

# Swap fw4/nftables for fw3/iptables-legacy (Android kernel has x_tables, not nf_tables)
opkg remove --force-depends \
    firewall4 nftables-json \
    kmod-nft-offload kmod-nft-nat kmod-nft-fib kmod-nft-core || true
opkg install iptables-zz-legacy ip6tables-zz-legacy firewall coreutils-base64
ln -sf /usr/sbin/iptables-legacy  /usr/sbin/iptables
ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables

# Android AID groups: root needs these or the kernel blocks AF_INET sockets
grep -q '^aid_inet:'      /etc/group || echo 'aid_inet:x:3003:root'      >> /etc/group
grep -q '^aid_net_raw:'   /etc/group || echo 'aid_net_raw:x:3004:root'   >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:root' >> /etc/group

# Confirm root's group membership via usermod, then drop shadow-utils
opkg install shadow-utils
usermod -a -G aid_inet,aid_net_raw root || true
opkg remove --force-depends shadow-utils

# Upstream over eth0 (Droidspaces NAT); VirtualAP adds vaplan0 LAN at start time
cat > /etc/config/network <<'NETEOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config interface 'wan'
	option device 'eth0'
	option proto 'dhcp'
NETEOF

# fw3 zones: vaplan lives in an isolated 'guest' zone (NOT lan) so hotspot
# clients reach only the internet (guest -> masqueraded wan/eth0) and never
# other containers on lan. input REJECT blocks router services by default; we
# punch holes below for DHCP + DNS (needed for a lease) and LuCI (admin UI).
cat > /etc/config/firewall <<'FWEOF'
config defaults
	option syn_flood '1'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'REJECT'

config zone
	option name 'lan'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'

config zone
	option name 'guest'
	list network 'vaplan'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'DROP'

config zone
	option name 'wan'
	list network 'wan'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option masq '1'
	option mtu_fix '1'

config forwarding
	option src 'lan'
	option dest 'wan'

config forwarding
	option src 'guest'
	option dest 'wan'

# Guest clients need DHCP + DNS from the router itself (input is REJECT)
config rule
	option name 'Allow-DHCP-Guest'
	option src 'guest'
	option proto 'udp'
	option dest_port '67-68'
	option target 'ACCEPT'

config rule
	option name 'Allow-DNS-Guest'
	option src 'guest'
	option proto 'tcp udp'
	option dest_port '53'
	option target 'ACCEPT'

# LuCI reachable from the hotspot (password-protected); router services otherwise blocked
config rule
	option name 'Allow-LuCI-Guest'
	option src 'guest'
	option proto 'tcp'
	option dest_port '80 443'
	option target 'ACCEPT'

config rule
	option name 'Allow-DHCP-Renew'
	option src 'wan'
	option proto 'udp'
	option dest_port '68'
	option family 'ipv4'
	option target 'ACCEPT'

config rule
	option name 'Allow-Ping'
	option src 'wan'
	option proto 'icmp'
	option icmp_type 'echo-request'
	option family 'ipv4'
	option target 'ACCEPT'

config rule
	option name 'Allow-LuCI-Droidspaces'
	option src 'wan'
	option src_ip '172.28.0.0/16'
	option proto 'tcp'
	option dest_port '80 443'
	option target 'ACCEPT'
FWEOF

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/30-virtualap.conf
echo "Droidspaces/VirtualAP OpenWrt image built on $(date)" > /etc/droidspaces

# Trim opkg lists; keep /tmp (resolv.conf symlink + tmpfs at runtime)
rm -rf /var/opkg-lists/* 2>/dev/null || true
EOF_RUN

# Stage 3: flatten to scratch for export
FROM scratch AS export
COPY --from=customizer / /
