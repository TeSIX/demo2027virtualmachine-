#!/usr/bin/env bash
# Модуль 2 · ISP: chrony — NTP-сервер stratum 5 для офисных сетей.
step "M2 · ISP: chrony stratum 5"
apt_install chrony
backup_file /etc/chrony.conf
write_file /etc/chrony.conf <<'EOF'
server time.cloudflare.com iburst minstratum 4
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow 172.16.1.0/28
allow 172.16.2.0/28
allow 192.168.100.0/27
allow 192.168.200.0/28
allow 192.168.30.0/28
EOF
svc_enable_now chronyd
run systemctl restart chronyd
run chronyc sources -v || true
run chronyc tracking || true
warn "В 'chronyc tracking' ожидается Stratum: 5 (клиенты при этом будут stratum 6)"
finish "ISP (модуль 2)"
