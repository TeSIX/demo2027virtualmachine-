#!/usr/bin/env bash
# Модуль 2 · HQ-SRV: RAID0 из двух доп. дисков -> раздел ext4 /raid, NFS для 192.168.200.0/28,
# Apache+PHP+MariaDB (webdb). RAID создаётся ТОЛЬКО при RAID_CONFIRM=YES в config.env!
step "M2 · HQ-SRV: chrony <- ISP 172.16.1.1"
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

step "M2 · HQ-SRV: RAID 0 (${RAID_DISKS:-/dev/sdb /dev/sdc})"
run lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
if [ "${RAID_CONFIRM:-}" != "YES" ]; then
  warn "RAID пропущен: выставьте RAID_CONFIRM=YES и верные RAID_DISKS в config.env (диски будут СТЁРТЫ)."
else
  confirm "Создать RAID0 из ${RAID_DISKS}? Все данные на этих дисках будут уничтожены" || die "Отменено"
  apt_install mdadm e2fsprogs parted
  # shellcheck disable=SC2086
  if [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] mdadm --create /dev/md0 --level=0 --raid-devices=2 %s; parted; mkfs.ext4 /dev/md0p1; fstab UUID->/raid\n' "$RAID_DISKS"
  else
    # shellcheck disable=SC2086
    mdadm --create /dev/md0 --level=0 --raid-devices=2 $RAID_DISKS
    cat /proc/mdstat; mdadm --detail /dev/md0
    parted -s /dev/md0 mklabel gpt
    parted -s /dev/md0 mkpart primary ext4 1MiB 100%
    partprobe /dev/md0; udevadm settle
    mkfs.ext4 -L RAID /dev/md0p1
    mkdir -p /raid
    backup_file /etc/mdadm.conf
    # НЕ `> /etc/mdadm.conf`: перезапись стирала существующие ARRAY/DEVICE (материал: внести строку, сохранив прочее)
    mdadm --detail --scan | while read -r line; do ensure_line /etc/mdadm.conf "$line"; done
    uuid="$(blkid -s UUID -o value /dev/md0p1)"
    grep -q "$uuid" /etc/fstab || printf 'UUID=%s /raid ext4 defaults 0 2\n' "$uuid" >> /etc/fstab
    systemctl daemon-reload; mount /raid; findmnt /raid
  fi
fi

step "M2 · HQ-SRV: NFS /raid/nfs только для клиентской подсети"
apt_install nfs-server
run mkdir -p /raid/nfs
if [ "$DRY_RUN" != "1" ]; then chown 65534:65534 /raid/nfs; chmod 0770 /raid/nfs; fi
ensure_line /etc/exports "/raid/nfs 192.168.200.0/28(rw,sync,all_squash,anonuid=65534,anongid=65534,no_subtree_check)"
svc_enable_now nfs-server
run exportfs -rav
run exportfs -v

step "M2 · HQ-SRV: Apache + PHP + MariaDB, БД webdb"
mount_additional
apt_install apache2 mariadb
# версия PHP — какая есть в p11
PHPV="$(apt-cache search '^php[0-9.]+$' 2>/dev/null | awk '{print $1}' | sort -V | tail -1)"
PHPV="${PHPV#php}"; PHPV="${PHPV:-8.3}"
log "Использую PHP $PHPV"
apt_install "apache2-mod_php${PHPV}" "php${PHPV}" "php${PHPV}-mysqli" || warn "Пакеты PHP $PHPV не нашлись — подберите: apt-cache search apache2-mod_php"
svc_enable_now mariadb
svc_enable_now httpd2
if [ "$DRY_RUN" = "1" ]; then
  printf '  [dry-run] CREATE DATABASE webdb; CREATE USER web@localhost; импорт dump.sql; vhost webapp\n'
else
  mariadb <<'SQL'
CREATE DATABASE IF NOT EXISTS webdb CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';
ALTER USER 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost';
FLUSH PRIVILEGES;
SQL
  if [ -f /mnt/additional/web/dump.sql ]; then mariadb webdb < /mnt/additional/web/dump.sql && ok "dump.sql импортирован"
  else warn "/mnt/additional/web/dump.sql не найден — импорт пропущен"; fi
  mkdir -p /var/www/html
  for f in index.php logo.png; do
    [ -f "/mnt/additional/web/$f" ] && { cp "/mnt/additional/web/$f" /var/www/html/; chmod 644 "/var/www/html/$f"; } \
      || warn "/mnt/additional/web/$f не найден"
  done
fi
write_file /etc/httpd2/conf/sites-available/webapp.conf <<EOF
<VirtualHost *:80>
    ServerName hq-srv.${DOMAIN}
    DocumentRoot /var/www/html
    DirectoryIndex index.php
    <Directory /var/www/html>
        Require all granted
        AllowOverride None
    </Directory>
</VirtualHost>
EOF
if [ "$DRY_RUN" != "1" ]; then
  a2enmod "mod_php${PHPV}" 2>/dev/null || a2enmod "php${PHPV}" 2>/dev/null || warn "a2enmod PHP — проверьте имя модуля в /etc/httpd2/conf/mods-available"
  a2ensite webapp 2>/dev/null || a2ensite webapp.conf 2>/dev/null || warn "a2ensite webapp не удался"
  apachectl -t 2>/dev/null || apache2ctl -t
  systemctl restart httpd2
  curl -s http://127.0.0.1/ | head -c 300; echo
  warn "В /var/www/html/index.php проверьте параметры подключения: localhost / webdb / web / P@ssw0rd"
fi
finish "HQ-SRV (модуль 2)"
