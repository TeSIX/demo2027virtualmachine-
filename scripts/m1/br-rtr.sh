#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m1/br-rtr.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" br-rtr 1 "$@"
fi
# --------------------------------------------------------------------------------
# Модуль 1 · BR-RTR: WAN 172.16.2.2/28, ens37=192.168.10.0/31 (к BR-FW),
# forwarding+NAT, net_admin, GRE->HQ-RTR, OSPF+MD5 (gre1 + линк к BR-FW).
step "M1 · BR-RTR: имя, время, адреса etcnet"
set_hostname_tz br-rtr
backup_dir /etc/net
eth_iface ens33 static 172.16.2.2/28 "default via 172.16.2.1"
eth_iface ens37 static 192.168.10.0/31
write_resolv_iface ens33 "search ${DOMAIN}" "nameserver 77.88.8.8"

step "M1 · BR-RTR: forwarding + NAT"
enable_forwarding
write_nat "192.168.30.0/28, 192.168.10.0/31"

step "M1 · BR-RTR: net_admin + sudo + sshd"
apt_install sudo openssh-server
make_user net_admin "" "${NET_ADMIN_PASSWORD:-}"
sudo_nopasswd net_admin
svc_enable_now sshd

step "M1 · BR-RTR: GRE к HQ-RTR (10.10.10.1/31)"
gre_iface 172.16.2.2 172.16.1.2 10.10.10.1/31
run modprobe ip_gre
run ifup gre1 || warn "ifup gre1 не удался — примените сеть и повторите"

step "M1 · BR-RTR: OSPF (router-id 2.2.2.2, MD5 на gre1)"
frr_ospf <<'EOF'
configure terminal
interface gre1
 ip ospf network point-to-point
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
exit
interface ens37
 ip ospf network point-to-point
exit
router ospf
 ospf router-id 2.2.2.2
 passive-interface default
 no passive-interface gre1
 no passive-interface ens37
 network 10.10.10.0/31 area 0
 network 192.168.10.0/31 area 0
exit
end
write memory
exit
EOF

apply_network
finish "BR-RTR (модуль 1)"
