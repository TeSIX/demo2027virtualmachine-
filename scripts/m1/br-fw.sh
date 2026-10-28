#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m1/br-fw.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" br-fw 1 "$@"
fi
# --------------------------------------------------------------------------------
# Модуль 1 · BR-FW: $IF1=192.168.10.1/31 (к BR-RTR, шлюз), $IF2=192.168.30.1/28 (к BR-SRV),
# forwarding, OSPF (соседство с BR-RTR, сеть BR-SRV — пассивно). NAT здесь НЕ делается.
step "M1 · BR-FW: имя, время, адреса etcnet"
set_hostname_tz br-fw
backup_dir /etc/net
eth_iface $IF1 static 192.168.10.1/31 "default via 192.168.10.0"
eth_iface $IF2 static 192.168.30.1/28
write_resolv_iface $IF1 "search ${DOMAIN}" "nameserver 77.88.8.8"

step "M1 · BR-FW: forwarding"
enable_forwarding

step "M1 · BR-FW: OSPF (router-id 3.3.3.3)"
frr_ospf <<EOF
configure terminal
interface $IF1
 ip ospf network point-to-point
exit
router ospf
 ospf router-id 3.3.3.3
 passive-interface default
 no passive-interface $IF1
 network 192.168.10.0/31 area 0
 network 192.168.30.0/28 area 0
exit
end
write memory
exit
EOF

apply_network
finish "BR-FW (модуль 1)"
