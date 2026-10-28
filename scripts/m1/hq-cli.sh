#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m1/hq-cli.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" hq-cli 1 "$@"
fi
# --------------------------------------------------------------------------------
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
