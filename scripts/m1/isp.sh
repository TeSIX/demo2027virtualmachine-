#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m1/isp.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" isp 1 "$@"
fi
# --------------------------------------------------------------------------------
# Модуль 1 · ISP: $IF1=DHCP(Интернет), $IF2=172.16.1.1/28 (к HQ), $IF3=172.16.2.1/28 (к BR),
# forwarding + NAT офисных трансляций. Выполняется из demo2027.sh.
step "M1 · ISP: имя, время, адреса etcnet"
set_hostname_tz isp
backup_dir /etc/net
eth_iface $IF1 dhcp
eth_iface $IF2 static 172.16.1.1/28
eth_iface $IF3 static 172.16.2.1/28
step "M1 · ISP: ip_forward + NAT"
enable_forwarding
write_nat "172.16.1.0/28, 172.16.2.0/28"
apply_network
finish "ISP (модуль 1)"
