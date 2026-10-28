#!/usr/bin/env bash
# Модуль 3 · HQ-SRV: сертификат 30 дней (SAN web+docker) для ISP, atop 420 c,
# CUPS + виртуальный PDF-принтер, fail2ban SSH (3/60с), бэкап restic в репозиторий irpo на HQ-CLI.
step "M3 · HQ-SRV: самоподписанный сертификат (30 дней)"
apt_install openssl
run install -d -m 700 /root/exam-pki
if [ "$DRY_RUN" = "1" ]; then
  printf '  [dry-run] openssl req -x509 ... -days 30 (SAN web/docker) в /root/exam-pki\n'
elif [ -f /root/exam-pki/sites.crt ] && [ -f /root/exam-pki/sites.key ]; then
  # Повторная генерация создала бы НОВЫЙ CA: ISP и HQ-CLI доверяли бы старому, HTTPS «сломался» бы.
  ok "Сертификат уже есть в /root/exam-pki — не перегенерирую. Свежий (30 дней) нужен — удалите sites.* вручную"
else
(
  cd /root/exam-pki
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 30 \
    -keyout sites.key -out sites.crt -subj "/CN=web.${DOMAIN}" \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign' \
    -addext 'extendedKeyUsage=serverAuth' \
    -addext "subjectAltName=DNS:web.${DOMAIN},DNS:docker.${DOMAIN}"
  cp sites.crt ca.crt; chmod 600 sites.key
  openssl verify -CAfile ca.crt sites.crt
  openssl x509 -in sites.crt -noout -dates -ext subjectAltName
  # временные копии для ISP/HQ-CLI (ключ потом удалить из /home/sshuser!)
  cp sites.key sites.crt ca.crt /home/sshuser/
  chown sshuser: /home/sshuser/sites.key /home/sshuser/sites.crt /home/sshuser/ca.crt
  chmod 600 /home/sshuser/sites.key; chmod 644 /home/sshuser/sites.crt /home/sshuser/ca.crt
)
warn "После передачи на ISP удалите ключ: rm /home/sshuser/sites.key (на HQ-CLI ключ НЕ нужен)"
fi

step "M3 · HQ-SRV: atop, интервал 420 секунд"
apt_install atop
run mkdir -p /var/log/atop-exam
write_file /etc/systemd/system/exam-atop.service <<'EOF'
[Unit]
Description=Atop collection every 7 minutes
After=local-fs.target
[Service]
Type=simple
ExecStart=/usr/bin/atop -w /var/log/atop-exam/metrics.raw 420
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
run systemctl daemon-reload
svc_enable_now exam-atop
[ "$DRY_RUN" = "1" ] || { systemctl list-unit-files '*atop*' | grep -q '^atop\.service' \
  && warn "Есть штатный atop.service — отключите дубль: systemctl disable --now atop" || true; }
run ls -lh /var/log/atop-exam || true

step "M3 · HQ-SRV: CUPS + PDF-принтер (сетевой, для 192.168.200.0/28)"
apt_install cups cups-pdf
svc_enable_now cups
if [ "$DRY_RUN" != "1" ]; then
  model="$(lpinfo -m 2>/dev/null | grep -i 'cups.*pdf' | head -1 | awk '{print $1}')"
  if [ -n "$model" ]; then
    lpstat -p PDF >/dev/null 2>&1 || lpadmin -p PDF -E -v cups-pdf:/ -m "$model"
    lpadmin -p PDF -o printer-is-shared=true
    lpoptions -d PDF
  else warn "Модель CUPS-PDF не найдена: lpinfo -m | grep -i pdf — создайте очередь вручную (см. материал)"; fi
  # доступ к CUPS: аккуратно дополняем cupsd.conf
  backup_file /etc/cups/cupsd.conf
  grep -q '192.168.100.2:631' /etc/cups/cupsd.conf || sed -i '/^Listen localhost:631/a Listen 192.168.100.2:631' /etc/cups/cupsd.conf
  grep -q 'Allow from 192.168.200.0/28' /etc/cups/cupsd.conf \
    || warn "В /etc/cups/cupsd.conf вручную добавьте в <Location />: Allow from 192.168.200.0/28 (блок Location автоматически не переписываю)"
  grep -q '^Browsing On' /etc/cups/cupsd.conf || printf 'Browsing On\nWebInterface Yes\n' >> /etc/cups/cupsd.conf
  sed -i 's|^AnonDirName.*|AnonDirName /var/spool/cups-pdf/ANONYMOUS|' /etc/cups/cups-pdf.conf 2>/dev/null || true
  mkdir -p /var/spool/cups-pdf/ANONYMOUS
  cupsd -t && systemctl restart cups
  lpstat -t || true
fi

step "M3 · HQ-SRV: fail2ban для SSH (3 попытки, бан 60 с)"
apt_install fail2ban nftables
run mkdir -p /etc/fail2ban/jail.d
write_file /etc/fail2ban/jail.d/ssh.local <<'EOF'
[ssh]
enabled = true
filter = sshd
port = 2027
backend = systemd
maxretry = 3
findtime = 600
bantime = 60
banaction = nftables-multiport
EOF
if [ "$DRY_RUN" != "1" ]; then
  ls /etc/fail2ban/action.d/nftables*.conf >/dev/null 2>&1 || warn "Нет действия nftables* — подберите имеющееся в /etc/fail2ban/action.d/"
  fail2ban-client -t
fi
svc_enable_now fail2ban
run systemctl restart fail2ban
run fail2ban-client status ssh || true

step "M3 · HQ-SRV: резервное копирование restic -> irpo на HQ-CLI"
if [ "$DRY_RUN" != "1" ] && [ ! -x /usr/local/bin/restic-exam ] && command -v restic >/dev/null; then
  ln -sf "$(command -v restic)" /usr/local/bin/restic-exam; ok "restic-exam -> системный restic"
fi
apt_install restic 2>/dev/null || warn "Пакет restic не установился; для версии из материала (0.16.5) используйте standalone-бинарник /usr/local/bin/restic-exam"
run mkdir -p /root/.ssh
[ "$DRY_RUN" = "1" ] || chmod 700 /root/.ssh
[ -f /root/.ssh/id_ed25519_irpo ] || run ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_irpo -N ''
write_file /root/.ssh/config 600 <<'EOF'
Host hq-cli-backup
    HostName 192.168.200.2
    User irpoadmin
    Port 22
    IdentityFile /root/.ssh/id_ed25519_irpo
    IdentitiesOnly yes
    BatchMode yes
    StrictHostKeyChecking yes
EOF
cat <<'EOF'
ВРУЧНУЮ один раз:
  ssh-copy-id -i /root/.ssh/id_ed25519_irpo.pub -p 22 irpoadmin@192.168.200.2
  ssh hq-cli-backup 'ls -ld /backup/irpo'
EOF
RESTIC="/usr/local/bin/restic-exam"; [ -x "$RESTIC" ] || RESTIC="$(command -v restic || echo /usr/local/bin/restic-exam)"
run install -d -m 700 /root/.config/restic
if [ -n "${RESTIC_REPO_PASSWORD:-}" ] && [ "$DRY_RUN" != "1" ]; then
  printf '%s\n' "$RESTIC_REPO_PASSWORD" > /root/.config/restic/irpo.password; chmod 600 /root/.config/restic/irpo.password
  REPO="sftp:hq-cli-backup:/backup/irpo"
  "$RESTIC" -r "$REPO" --password-file /root/.config/restic/irpo.password snapshots >/dev/null 2>&1 \
    || "$RESTIC" -r "$REPO" --password-file /root/.config/restic/irpo.password init
  "$RESTIC" -r "$REPO" --password-file /root/.config/restic/irpo.password backup --host hq-srv --tag irpo /etc /home /root
  "$RESTIC" -r "$REPO" --password-file /root/.config/restic/irpo.password snapshots
  "$RESTIC" -r "$REPO" --password-file /root/.config/restic/irpo.password check
else
  warn "RESTIC_REPO_PASSWORD пуст в config.env — init/backup пропущены. Задайте пароль и повторите, либо выполните вручную (см. материал п.9.4)"
fi
# systemd timer ежедневного бэкапа
{
  printf '[Unit]\nDescription=Backup HQ-SRV to irpo on HQ-CLI\nWants=network-online.target\nAfter=network-online.target\n'
  printf '[Service]\nType=oneshot\nExecStart=%s -r sftp:hq-cli-backup:/backup/irpo --password-file /root/.config/restic/irpo.password backup --host hq-srv --tag irpo /etc /home /root\n' "$RESTIC"
} | write_file /etc/systemd/system/backup-irpo.service
write_file /etc/systemd/system/backup-irpo.timer <<'EOF'
[Unit]
Description=Daily irpo backup
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
run systemctl daemon-reload
run systemctl enable --now backup-irpo.timer
warn "Проверка восстановления: restic restore latest --target /root/restore-irpo-test --include /etc/passwd (см. материал п.9.6)"
finish "HQ-SRV (модуль 3)"
