#!/usr/bin/env bash
# Модуль 3 · HQ-CLI: доверие CA (web/docker без предупреждений), CUPS-клиент HQ-PDF по умолчанию,
# пользователь irpoadmin + каталог /backup/irpo для бэкапов HQ-SRV.
step "M3 · HQ-CLI: доверие сертификату HQ-SRV"
apt_install openssl ca-certificates
if [ "$DRY_RUN" != "1" ]; then
  scp -P 2027 sshuser@192.168.100.2:/home/sshuser/ca.crt /tmp/au-team-ca.crt \
    && { openssl x509 -in /tmp/au-team-ca.crt -noout -fingerprint -sha256
         trust anchor --store /tmp/au-team-ca.crt && trust extract-compat \
           && ok "CA установлен в системное хранилище (сверьте отпечаток с HQ-SRV!)"; } \
    || warn "Не удалось забрать ca.crt: сначала выполните m3 на hq-srv"
  curl -s -o /dev/null -w 'docker https: %{http_code}\n' "https://docker.${DOMAIN}/" || warn "docker https — проверьте DNS/сертификат"
  curl -s -o /dev/null -w 'web https (401 без пароля — норма): %{http_code}\n' "https://web.${DOMAIN}/" || true
  warn "В Яндекс Браузере при необходимости импортируйте ca.crt в доверенные ЦС и перезапустите браузер"
fi

step "M3 · HQ-CLI: сетевой PDF-принтер по умолчанию"
apt_install cups
svc_enable_now cups
if [ "$DRY_RUN" != "1" ]; then
  lpstat -p HQ-PDF >/dev/null 2>&1 || lpadmin -p HQ-PDF -E -v "ipp://hq-srv.${DOMAIN}:631/printers/PDF" -m everywhere \
    || warn "lpadmin HQ-PDF не удался — если очередь не driverless, укажите PPD CUPS-PDF вручную"
  lpoptions -d HQ-PDF || true
  lpstat -d || true
  warn "Тест: lp -d HQ-PDF /etc/hostname ; PDF ищите на HQ-SRV в /var/spool/cups-pdf/ANONYMOUS"
fi

step "M3 · HQ-CLI: хранилище бэкапов irpo"
apt_install openssh-server
make_user irpoadmin "" "${IRPOADMIN_PASSWORD:-}"
if [ "$DRY_RUN" != "1" ]; then
  mkdir -p /backup/irpo
  chown irpoadmin: /backup /backup/irpo
  chmod 700 /backup /backup/irpo
  grep -q '^AllowUsers' /etc/openssh/sshd_config \
    && warn "В sshd_config есть AllowUsers — добавьте irpoadmin вручную: $(grep '^AllowUsers' /etc/openssh/sshd_config)"
fi
svc_enable_now sshd
run ls -ld /backup /backup/irpo || true
finish "HQ-CLI (модуль 3)"
