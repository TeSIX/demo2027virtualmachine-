#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m1/hq-sw.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" hq-sw 1 "$@"
fi
# --------------------------------------------------------------------------------
# Модуль 1 · HQ-SW (вариант: отдельная Linux-ВМ): мост br0 с VLAN-filtering.
# $IF1=trunk к HQ-RTR (100/200/999), $IF2=access VLAN100 к HQ-SRV,
# $IF3=access VLAN200 к HQ-CLI, управление br0.999 = 192.168.99.2/29.
# Если VLAN настроены в гипервизоре — этот скрипт НЕ нужен.
step "M1 · HQ-SW: Linux-коммутатор VLAN 100/200/999"
confirm "Настроить Linux-мост br0 на $IF1/$IF2/$IF3 этой ВМ? Текущие адреса интерфейсов будут потеряны" \
  || die "Отменено пользователем"

# ip/bridge нужны живыми; если их нет — ставим, пока на ВМ есть временный NAT-адаптер
command -v ip >/dev/null && command -v bridge >/dev/null || apt_install iproute2

# etcnet НЕ должен управлять портами моста: иначе при перезапуске сети он будет
# дёргать интерфейсы, уже включённые в br0. Оставляем ему только ONBOOT=no.
step "M1 · HQ-SW: отключаем порты моста от etcnet"
for _port in "$IF1" "$IF2" "$IF3"; do
  run mkdir -p "/etc/net/ifaces/$_port"
  printf 'TYPE=eth\nBOOTPROTO=static\nONBOOT=no\nDISABLED=no\nNM_CONTROLLED=no\nSYSTEMD_CONTROLLED=no\nCONFIG_IPV4=no\nCONFIG_IPV6=no\n' \
    | write_file "/etc/net/ifaces/$_port/options"
  if [ "$DRY_RUN" != "1" ]; then : > "/etc/net/ifaces/$_port/ipv4address"; : > "/etc/net/ifaces/$_port/ipv4route"; fi
done

write_file /etc/systemd/system/hq-switch.service <<EOF
[Unit]
Description=HQ VLAN switch
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip link add br0 type bridge vlan_filtering 1 vlan_default_pvid 0
ExecStart=/usr/sbin/ip link set br0 up
ExecStart=/usr/sbin/ip link set $IF1 master br0
ExecStart=/usr/sbin/ip link set $IF1 up
ExecStart=/usr/sbin/ip link set $IF2 master br0
ExecStart=/usr/sbin/ip link set $IF2 up
ExecStart=/usr/sbin/ip link set $IF3 master br0
ExecStart=/usr/sbin/ip link set $IF3 up
ExecStart=/usr/sbin/bridge vlan add dev $IF1 vid 100
ExecStart=/usr/sbin/bridge vlan add dev $IF1 vid 200
ExecStart=/usr/sbin/bridge vlan add dev $IF1 vid 999
ExecStart=/usr/sbin/bridge vlan add dev $IF2 vid 100 pvid untagged
ExecStart=/usr/sbin/bridge vlan add dev $IF3 vid 200 pvid untagged
ExecStart=/usr/sbin/bridge vlan add vid 999 dev br0 self
ExecStart=/usr/sbin/ip link add link br0 name br0.999 type vlan id 999
ExecStart=/usr/sbin/ip addr add 192.168.99.2/29 dev br0.999
ExecStart=/usr/sbin/ip link set br0.999 up
ExecStart=-/usr/sbin/ip route add default via 192.168.99.1
[Install]
WantedBy=multi-user.target
EOF
run systemctl daemon-reload
run systemctl enable hq-switch
if [ "$DRY_RUN" != "1" ] && ! ip link show br0 >/dev/null 2>&1; then
  systemctl start hq-switch || warn "hq-switch не стартовал — проверьте: journalctl -u hq-switch"
fi
run bridge vlan show || true
finish "HQ-SW (модуль 1)"
