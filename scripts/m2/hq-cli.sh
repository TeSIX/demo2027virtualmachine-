#!/usr/bin/env bash
# Модуль 2 · HQ-CLI: время от ISP(HQ)=172.16.1.1, sshuser для Ansible, ввод в домен AU-TEAM.IRPO,
# sudo только cat/grep/id для группы hq, NFS-клиент (автомонтирование /mnt/nfs), Яндекс Браузер.
step "M2 · HQ-CLI: chrony <- ISP 172.16.1.1"
apt_install chrony
backup_file /etc/chrony.conf
write_file /etc/chrony.conf <<'EOF'
server 172.16.1.1 iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF
svc_enable_now chronyd
run systemctl restart chronyd
run chronyc tracking || true

step "M2 · HQ-CLI: sshuser для Ansible (порт 22)"
apt_install openssh-server sudo python3
make_user sshuser "" "${SSHUSER_PASSWORD:-}"
sudo_nopasswd sshuser
svc_enable_now sshd

step "M2 · HQ-CLI: ввод в домен ${DOMAIN}"
apt_install task-auth-ad-sssd bind-utils sudo
run control sudo public || true
if [ -z "${DOMAIN_ADMIN_PASSWORD:-}" ]; then
  warn "DOMAIN_ADMIN_PASSWORD пуст в config.env — ввод в домен пропущен. Выполните вручную:"
  cat <<EOF
  system-auth write ad ${DOMAIN} hq-cli AU-TEAM administrator '<пароль администратора домена>'
  reboot
EOF
elif [ "$DRY_RUN" = "1" ]; then
  printf '  [dry-run] system-auth write ad %s hq-cli AU-TEAM administrator ***\n' "$DOMAIN"
else
  system-auth write ad "$DOMAIN" hq-cli AU-TEAM administrator "$DOMAIN_ADMIN_PASSWORD"
  warn "HQ-CLI уйдёт в перезагрузку для применения домена (как в материале)"
  confirm "Перезагрузить HQ-CLI сейчас?" && reboot || warn "Перезагрузите вручную: reboot"
fi
# Содержимое sudoers для доменной группы (применится, когда группа видна через SSSD)
printf '%%hq@%s ALL=(root) /usr/bin/cat, /usr/bin/grep, /usr/bin/id\n' "$DOMAIN" | write_file /etc/sudoers.d/hq 440
[ "$DRY_RUN" = "1" ] || { chmod 440 /etc/sudoers.d/hq; visudo -c; sudo -l -U "hquser1@${DOMAIN}" || warn "Проверьте sudo -l после входа в домен и перезагрузки"; }
warn "Если SSSD отдаёт группу коротким именем, замените %hq@${DOMAIN} на %hq в /etc/sudoers.d/hq"

step "M2 · HQ-CLI: NFS-клиент"
apt_install nfs-clients
svc_enable_now nfs-client.target || true
run mkdir -p /mnt/nfs
ensure_line /etc/fstab "192.168.100.2:/raid/nfs /mnt/nfs nfs4 rw,_netdev,x-systemd.automount,x-systemd.idle-timeout=60 0 0"
run systemctl daemon-reload
run systemctl start mnt-nfs.automount || true
run ls /mnt/nfs || warn "NFS пока недоступен — проверьте экспорт на HQ-SRV и подсеть"

step "M2 · HQ-CLI: Яндекс Браузер"
if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] apt-get install -y yandex-browser-stable\n'
else
  apt-get install -y yandex-browser-stable || warn "Пакета нет в репозиториях: установите официальный RPM для ALT: apt-get install /путь/yandex-browser*.rpm (НЕ .deb)"
  rpm -q yandex-browser-stable || true
fi
finish "HQ-CLI (модуль 2)"
