#!/usr/bin/env bash
# Модуль 1 · HQ-CLI: ens33 по DHCP (резерв 192.168.200.2 на HQ-RTR), имя и время.
# DHCP-сервер появляется только в п.9 модуля 1 (hq-rtr) — до этого адреса может не быть.
step "M1 · HQ-CLI: имя, время, DHCP etcnet"
set_hostname_tz hq-cli
backup_dir /etc/net
eth_iface ens33 dhcp
svc_enable_now network || run systemctl enable network
warn "Переподнятие ens33 выполняйте из консоли ВМ: ifdown ens33; ifup ens33 (SSH разорвётся)"
run ip -br address || true
finish "HQ-CLI (модуль 1)"
