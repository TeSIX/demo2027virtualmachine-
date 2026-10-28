#!/usr/bin/env bash
# Модуль 1 · BR-SRV: 192.168.30.2/28, sshuser(UID 2027)+sudo, SSH 2027.
# Внимание: Samba DC на BR-SRV уже работает (стенд модуля 2) — скрипт её НЕ трогает.
step "M1 · BR-SRV: имя, время, адрес etcnet"
set_hostname_tz br-srv
backup_dir /etc/net
eth_iface ens33 static 192.168.30.2/28 "default via 192.168.30.1"
write_resolv_iface ens33 "search ${DOMAIN}" "nameserver 77.88.8.8"

step "M1 · BR-SRV: sshuser + sudo"
apt_install sudo openssh-server
make_user sshuser 2027 "${SSHUSER_PASSWORD:-}"
sudo_nopasswd sshuser

step "M1 · BR-SRV: SSH порт 2027"
configure_sshd_exam

apply_network
# После запуска DNS на HQ-SRV (m1 hq-srv) внутренний резолвер:
write_resolv_iface ens33 "search ${DOMAIN}" "nameserver 192.168.100.2"
finish "BR-SRV (модуль 1)"
