#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m1/hq-srv.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" hq-srv 1 "$@"
fi
# --------------------------------------------------------------------------------
# Модуль 1 · HQ-SRV: 192.168.100.2/27, sshuser(UID 2027)+sudo, SSH 2027, DNS dnsmasq (A/PTR+forward).
step "M1 · HQ-SRV: имя, время, адрес etcnet"
set_hostname_tz hq-srv
backup_dir /etc/net
eth_iface $IF1 static 192.168.100.2/27 "default via 192.168.100.1"
write_resolv_iface $IF1 "search ${DOMAIN}" "nameserver 77.88.8.8"

step "M1 · HQ-SRV: sshuser + sudo"
apt_install sudo openssh-server
make_user sshuser 2027 "${SSHUSER_PASSWORD:-}"
sudo_nopasswd sshuser

step "M1 · HQ-SRV: SSH порт 2027"
configure_sshd_exam

step "M1 · HQ-SRV: применяем сеть ДО запуска DNS"
# Иначе dnsmasq (bind-interfaces, listen-address=192.168.100.2) на первом запуске
# не найдёт свой адрес и упадёт, оборвав скрипт до apply_network.
apply_network

step "M1 · HQ-SRV: DNS (dnsmasq)"
apt_install dnsmasq bind-utils
run ss -lntup | grep ':53 ' || true
backup_file /etc/dnsmasq.conf
write_file /etc/dnsmasq.conf <<EOF
interface=$IF1
listen-address=127.0.0.1,192.168.100.2
bind-interfaces
no-resolv
server=77.88.8.8
server=77.88.8.1
domain=${DOMAIN}
local=/${DOMAIN}/
host-record=hq-rtr.${DOMAIN},192.168.100.1
host-record=br-rtr.${DOMAIN},192.168.10.0
host-record=br-fw.${DOMAIN},192.168.30.1
host-record=hq-srv.${DOMAIN},192.168.100.2
host-record=hq-cli.${DOMAIN},192.168.200.2
host-record=br-srv.${DOMAIN},192.168.30.2
host-record=docker.${DOMAIN},172.16.1.1
host-record=web.${DOMAIN},172.16.2.1
EOF
[ "$DRY_RUN" = "1" ] || { dnsmasq --test; }
svc_enable_now dnsmasq
[ "$DRY_RUN" = "1" ] || systemctl restart dnsmasq   # перечитать конфиг при повторном запуске
write_resolv_iface $IF1 "search ${DOMAIN}" "nameserver 127.0.0.1"

run dig @192.168.100.2 "hq-srv.${DOMAIN}" A +short || true
run dig @192.168.100.2 -x 192.168.100.2 +short || true
finish "HQ-SRV (модуль 1)"
