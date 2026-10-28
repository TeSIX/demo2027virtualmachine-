#!/usr/bin/env bash
# Модуль 1 · HQ-RTR: WAN 172.16.1.2/28, trunk ens37 без IP, VLAN 100/200/999,
# forwarding+NAT, пользователь net_admin, GRE->BR-RTR, OSPF+MD5, DHCP для HQ-CLI.
step "M1 · HQ-RTR: имя, время, адреса etcnet, VLAN"
set_hostname_tz hq-rtr
backup_dir /etc/net
eth_iface ens33 static 172.16.1.2/28 "default via 172.16.1.1"
eth_iface ens37 static
vlan_iface vlan100 ens37 100 192.168.100.1/27
vlan_iface vlan200 ens37 200 192.168.200.1/28
vlan_iface vlan999 ens37 999 192.168.99.1/29
write_resolv_iface ens33 "search ${DOMAIN}" "nameserver 77.88.8.8"

step "M1 · HQ-RTR: forwarding + NAT"
enable_forwarding
write_nat "192.168.100.0/27, 192.168.200.0/28, 192.168.99.0/29"

step "M1 · HQ-RTR: net_admin + sudo + sshd"
apt_install sudo openssh-server
make_user net_admin "" "${NET_ADMIN_PASSWORD:-}"
sudo_nopasswd net_admin
svc_enable_now sshd

step "M1 · HQ-RTR: GRE к BR-RTR (10.10.10.0/31)"
gre_iface 172.16.1.2 172.16.2.2 10.10.10.0/31
run modprobe ip_gre
run ifup gre1 || warn "ifup gre1 не удался — примените сеть (apply ниже) и повторите"

step "M1 · HQ-RTR: OSPF (router-id 1.1.1.1, MD5 на gre1)"
frr_ospf <<'EOF'
configure terminal
interface gre1
 ip ospf network point-to-point
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
exit
router ospf
 ospf router-id 1.1.1.1
 passive-interface default
 no passive-interface gre1
 network 10.10.10.0/31 area 0
 network 192.168.100.0/27 area 0
 network 192.168.200.0/28 area 0
 network 192.168.99.0/29 area 0
exit
end
write memory
exit
EOF

step "M1 · HQ-RTR: применяем сеть ДО запуска DHCP"
# dnsmasq с bind-interfaces на vlan200 упадёт, если VLAN ещё не поднят (первый запуск),
# а падение enable --now под set -e оборвало бы скрипт до apply_network.
apply_network

step "M1 · HQ-RTR: DHCP (dnsmasq, только VLAN200)"
apt_install dnsmasq
backup_file /etc/dnsmasq.conf
write_file /etc/dnsmasq.conf <<EOF
port=0
interface=vlan200
bind-interfaces
dhcp-authoritative
dhcp-range=192.168.200.2,192.168.200.14,255.255.255.240,12h
dhcp-option=3,192.168.200.1
dhcp-option=6,192.168.100.2
dhcp-option=15,${DOMAIN}
dhcp-host=${HQ_CLI_MAC:-52:54:00:12:34:56},192.168.200.2,hq-cli,infinite
EOF
[ "$DRY_RUN" = "1" ] || dnsmasq --test
svc_enable_now dnsmasq
[ "$DRY_RUN" = "1" ] || systemctl restart dnsmasq   # enable --now не перечитает конфиг у работающей службы

run ping -c 3 10.10.10.1 || warn "GRE/OSPF ещё могут сходиться — проверьте: vtysh -c 'show ip ospf neighbor'"
finish "HQ-RTR (модуль 1)"
