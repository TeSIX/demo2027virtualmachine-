#!/usr/bin/env bash
# --- Автозапуск через диспетчер -------------------------------------------------
# Этот файл — ФРАГМЕНТ: все функции (step, eth_iface, write_file, apt_install…)
# определены в scripts/lib/common.sh и подключаются только из demo2027.sh.
# При прямом запуске (bash scripts/m2/br-rtr.sh) сами перенаправляем в диспетчер:
# иначе будет «command not found» на каждой функции.
if [ -z "${DEMO2027_DISPATCHED:-}" ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/demo2027.sh" br-rtr 2 "$@"
fi
# --------------------------------------------------------------------------------
# Модуль 2 · BR-RTR: chrony-клиент + DNAT 8080->BR-SRV:8080, 2027->BR-SRV:2027.
step "M2 · BR-RTR: chrony <- ISP 172.16.2.1"
apt_install chrony python3
backup_file /etc/chrony.conf
write_file /etc/chrony.conf <<'EOF'
server 172.16.2.1 iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF
svc_enable_now chronyd
run systemctl restart chronyd

step "M2 · BR-RTR: DNAT (exam.nft целиком: postrouting + prerouting)"
tmp="$(mktemp)"
cat > "$tmp" <<EOF
 chain prerouting {
  type nat hook prerouting priority dstnat; policy accept;
  iifname "$IF1" ip daddr 172.16.2.2 tcp dport 8080 dnat to 192.168.30.2:8080
  iifname "$IF1" ip daddr 172.16.2.2 tcp dport 2027 dnat to 192.168.30.2:2027
 }
EOF
write_nat "192.168.30.0/28, 192.168.10.0/31" "$tmp"
rm -f "$tmp"
warn "Проверка делается с ISP: curl http://172.16.2.2:8080/ ; ssh -p 2027 sshuser@172.16.2.2"
finish "BR-RTR (модуль 2)"
