#!/usr/bin/env bash
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
cat > "$tmp" <<'EOF'
 chain prerouting {
  type nat hook prerouting priority dstnat; policy accept;
  iifname "ens33" ip daddr 172.16.2.2 tcp dport 8080 dnat to 192.168.30.2:8080
  iifname "ens33" ip daddr 172.16.2.2 tcp dport 2027 dnat to 192.168.30.2:2027
 }
EOF
write_nat "192.168.30.0/28, 192.168.10.0/31" "$tmp"
rm -f "$tmp"
warn "Проверка делается с ISP: curl http://172.16.2.2:8080/ ; ssh -p 2027 sshuser@172.16.2.2"
finish "BR-RTR (модуль 2)"
