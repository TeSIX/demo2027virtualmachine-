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
# ens33=trunk к HQ-RTR (100/200/999), ens37=access VLAN100 к HQ-SRV,
# ens38=access VLAN200 к HQ-CLI, управление br0.999 = 192.168.99.2/29.
# Если VLAN настроены в гипервизоре — этот скрипт НЕ нужен.
step "M1 · HQ-SW: Linux-коммутатор VLAN 100/200/999"
confirm "Настроить Linux-мост br0 на ens33/ens37/ens38 этой ВМ? Текущие адреса интерфейсов будут потеряны" \
  || die "Отменено пользователем"

write_file /etc/systemd/system/hq-switch.service <<'EOF'
[Unit]
Description=HQ VLAN switch
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip link add br0 type bridge vlan_filtering 1 vlan_default_pvid 0
ExecStart=/usr/sbin/ip link set br0 up
ExecStart=/usr/sbin/ip link set ens33 master br0
ExecStart=/usr/sbin/ip link set ens33 up
ExecStart=/usr/sbin/ip link set ens37 master br0
ExecStart=/usr/sbin/ip link set ens37 up
ExecStart=/usr/sbin/ip link set ens38 master br0
ExecStart=/usr/sbin/ip link set ens38 up
ExecStart=/usr/sbin/bridge vlan add dev ens33 vid 100
ExecStart=/usr/sbin/bridge vlan add dev ens33 vid 200
ExecStart=/usr/sbin/bridge vlan add dev ens33 vid 999
ExecStart=/usr/sbin/bridge vlan add dev ens37 vid 100 pvid untagged
ExecStart=/usr/sbin/bridge vlan add dev ens38 vid 200 pvid untagged
ExecStart=/usr/sbin/bridge vlan add vid 999 dev br0 self
ExecStart=/usr/sbin/ip link add link br0 name br0.999 type vlan id 999
ExecStart=/usr/sbin/ip addr add 192.168.99.2/29 dev br0.999
ExecStart=/usr/sbin/ip link set br0.999 up
ExecStart=/usr/sbin/ip route add default via 192.168.99.1
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
