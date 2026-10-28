#!/usr/bin/env bash
# Общая библиотека DEMO2027 (Альт Сервер 11.1, etcnet). Подключается из demo2027.sh.
# shellcheck shell=bash

# ---------- вывод ----------
_c() { printf '\033[%sm' "$1"; }
log()  { printf '%s[DEMO2027]%s %s\n' "$(_c '1;36')" "$(_c 0)" "$*"; }
ok()   { printf '%s[  OK  ]%s %s\n'  "$(_c '1;32')" "$(_c 0)" "$*"; }
warn() { printf '%s[ WARN ]%s %s\n'  "$(_c '1;33')" "$(_c 0)" "$*" >&2; }
err()  { printf '%s[ ERROR ]%s %s\n' "$(_c '1;31')" "$(_c 0)" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s===== %s =====%s\n' "$(_c '1;35')" "$*" "$(_c 0)"; }

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

# ---------- имена интерфейсов ----------
# Материал называет адаптеры $IF1/$IF2/$IF3, но гипервизор может дать другие
# имена (напр. второй адаптер = ens34, altname enp2s2 — подтверждено на BR-RTR).
# Поэтому: IF1/IF2/IF3 = 1-й/2-й/3-й ФИЗИЧЕСКИЙ интерфейс по порядку.
# Вручную задаются в config.env: IFACE1=..., IFACE2=..., IFACE3=...
_phys_ifaces() {
  local d n
  for d in /sys/class/net/*; do
    n="${d##*/}"
    case "$n" in ens*|enp*|eth*|enx*) [ -e "$d/device" ] && printf '%s\n' "$n" ;; esac
  done | sort -V
}
mapfile -t _PHYS_IFACES < <(_phys_ifaces)
IF1="${IFACE1:-${_PHYS_IFACES[0]:-}}"; [ -n "$IF1" ] || IF1="ens33"
IF2="${IFACE2:-${_PHYS_IFACES[1]:-}}"; [ -n "$IF2" ] || IF2="ens37"
IF3="${IFACE3:-${_PHYS_IFACES[2]:-}}"; [ -n "$IF3" ] || IF3="ens38"
export IF1 IF2 IF3
log "Интерфейсы: IF1=$IF1 IF2=$IF2 IF3=$IF3 (физических найдено: ${_PHYS_IFACES[*]:-нет})"

# Выполнить команду (в --dry-run только показать)
run() {
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] %s\n' "$*"; else log "+ $*"; "$@"; fi
}

need_root() {
  [ "$(id -u)" = "0" ] || die "Нужен root. Запустите: su - -c '$0 $*'"
  case "$(cat /etc/os-release 2>/dev/null | grep -E '^(ID|NAME)=')" in
    *alt*|*ALT*) : ;;
    *) warn "ОС не похожа на ALT Linux ($(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2-)). Продолжаю, но скрипты рассчитаны на Альт Сервер 11.1 / etcnet." ;;
  esac
}

confirm() { # confirm "вопрос"
  [ "$DRY_RUN" = "1" ] && { printf '  [dry-run] подтверждение пропущено: %s\n' "$1"; return 0; }
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -t 0 ] || die "Неинтерактивный запуск разрушающей операции запрещён. Добавьте --yes, если уверены: $1"
  local a; printf '%s [y/N] ' "$1"; read -r a; [ "$a" = "y" ] || [ "$a" = "Y" ]
}

# ---------- резервные копии ----------
BACKUP_ROOT="${BACKUP_ROOT:-/root/demo2027-backup}"
backup_file() { # backup_file /path/to/file
  local f="$1" dst
  [ -e "$f" ] || return 0
  dst="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)${f}"
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] backup %s -> %s\n' "$f" "$dst"; return 0; fi
  mkdir -p "$(dirname "$dst")"; cp -a "$f" "$dst"; log "backup: $f -> $dst"
}
backup_dir() {
  local d="$1" dst
  [ -d "$d" ] || return 0
  dst="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)${d}"
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] backup dir %s -> %s\n' "$d" "$dst"; return 0; fi
  mkdir -p "$(dirname "$dst")"; cp -a "$d" "$dst"
}

# ---------- запись файлов ----------
# write_file /path/to/file   — содержимое читается со stdin, права 644
write_file() {
  local f="$1" mode="${2:-644}" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] записать %s (mode %s):\n' "$f" "$mode"; sed 's/^/    | /' "$tmp"
  else
    backup_file "$f"; mkdir -p "$(dirname "$f")"; install -m "$mode" "$tmp" "$f"; ok "записан $f"
  fi
  rm -f "$tmp"
}

# Добавить строку, если такой ещё нет
ensure_line() { # ensure_line file "строка"
  local f="$1" line="$2"
  [ -f "$f" ] && grep -qxF "$line" "$f" && { ok "уже есть в $f: $line"; return 0; }
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] добавить в %s: %s\n' "$f" "$line"; return 0; fi
  backup_file "$f"; mkdir -p "$(dirname "$f")"; printf '%s\n' "$line" >> "$f"; ok "добавлено в $f: $line"
}

# Установить KEY=VALUE / KEY VALUE в конфиге (заменяет существующую активную строку)
set_kv() { # set_kv file KEY VALUE [separator]
  local f="$1" key="$2" val="$3" sep="${4:-=}"
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] %s: %s%s%s\n' "$f" "$key" "$sep" "$val"; return 0; fi
  backup_file "$f"; mkdir -p "$(dirname "$f")"; touch "$f"
  if grep -qE "^[#[:space:]]*${key}([[:space:]]|${sep})" "$f"; then
    sed -i -E "s|^[#[:space:]]*${key}([[:space:]]\|${sep}).*|${key}${sep}${val}|" "$f"
  else
    printf '%s%s%s\n' "$key" "$sep" "$val" >> "$f"
  fi
  ok "$f: $key$sep$val"
}

# ---------- пакеты / службы ----------
apt_install() {
  [ "$#" -gt 0 ] || return 0
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] apt-get install -y %s\n' "$*"; return 0; fi
  log "apt-get update (может занять время)…"
  apt-get update || warn "apt-get update завершился с ошибкой — проверьте репозитории/Интернет"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}
svc() { # svc enable|restart|... unit
  run systemctl "$@"
}
svc_enable_now() { run systemctl enable --now "$1"; }

# ---------- сеть etcnet ----------
# eth_iface $IF1 dhcp | eth_iface $IF2 static 172.16.1.1/28 "default via ..."
eth_iface() {
  local iface="$1" proto="$2" addr="${3:-}" route="${4:-}"
  local dir="/etc/net/ifaces/$iface"
  run mkdir -p "$dir"
  if [ "$proto" = "dhcp" ]; then
    write_file "$dir/options" <<EOF
TYPE=eth
BOOTPROTO=dhcp
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
CONFIG_WIRELESS=no
EOF
    # убрать старые статические адрес/шлюз, если были
    if [ "$DRY_RUN" != "1" ]; then : > "$dir/ipv4address"; : > "$dir/ipv4route"; else printf '  [dry-run] очистить %s/ipv4address и ipv4route\n' "$dir"; fi
  else
    write_file "$dir/options" <<EOF
TYPE=eth
BOOTPROTO=static
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
CONFIG_WIRELESS=no
EOF
    [ -n "$addr" ]  && printf '%s\n' "$addr"  | write_file "$dir/ipv4address"
    if [ -n "$route" ]; then printf '%s\n' "$route" | write_file "$dir/ipv4route"
    elif [ "$DRY_RUN" != "1" ]; then : > "$dir/ipv4route"   # убрать СТАРЫЙ default route (материал, п.1)
    else printf '  [dry-run] очистить %s/ipv4route (шлюз не задан)\n' "$dir"; fi
    if [ -z "$addr" ] && [ "$DRY_RUN" != "1" ]; then : > "$dir/ipv4address"; fi
  fi
}

vlan_iface() { # vlan_iface vlan100 $IF2 100 192.168.100.1/27
  local name="$1" host="$2" vid="$3" addr="$4" dir="/etc/net/ifaces/$1"
  run mkdir -p "$dir"
  write_file "$dir/options" <<EOF
TYPE=vlan
HOST=$host
VID=$vid
BOOTPROTO=static
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
EOF
  printf '%s\n' "$addr" | write_file "$dir/ipv4address"
}

gre_iface() { # gre_iface 172.16.1.2 172.16.2.2 10.10.10.0/31
  local local_ip="$1" remote_ip="$2" addr="$3" dir="/etc/net/ifaces/gre1"
  run mkdir -p "$dir"
  write_file "$dir/options" <<EOF
TYPE=iptun
TUNTYPE=gre
HOST=$IF1
TUNLOCAL=$local_ip
TUNREMOTE=$remote_ip
TUNOPTIONS='ttl 64'
MTU=1476
BOOTPROTO=static
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
CONFIG_IPV4=yes
CONFIG_IPV6=no
EOF
  printf '%s\n' "$addr" | write_file "$dir/ipv4address"
}

write_resolv_iface() { # write_resolv_iface $IF1 "nameserver ..."
  local iface="$1"; shift
  printf '%s\n' "$@" | write_file "/etc/net/ifaces/$iface/resolv.conf"
  printf '%s\n' "$@" | write_file "/etc/resolv.conf"
}

apply_network() {
  warn "Перезапуск сети может разорвать SSH! Выполняйте из консоли гипервизора."
  svc_enable_now network || run systemctl enable network
  run systemctl restart network
  # ВАЖНО: перезапуск сети (etcnet) может сбросить net.ipv4.ip_forward в 0
  # (подтверждено на BR-RTR: файл sysctl на месте, NAT работает, а forwarding=0 —
  # и транзит BR-FW -> ISP мёртв). Поэтому sysctl применяем ПОВТОРНО после сети.
  run sysctl --system
  run sysctl net.ipv4.ip_forward || true
  run ip -br address
  run ip route
}

set_hostname_tz() { # set_hostname_tz hq-rtr
  local short="$1"
  run hostnamectl set-hostname "${short}.${DOMAIN:-au-team.irpo}"
  run timedatectl set-timezone "${TIMEZONE:-Asia/Irkutsk}"
  run hostname -f || true
  run timedatectl || true
}

enable_forwarding() {
  write_file /etc/sysctl.d/90-exam-router.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.$IF1.rp_filter=0
net.ipv4.conf.$IF2.rp_filter=0
net.ipv4.conf.$IF3.rp_filter=0
EOF
  run sysctl --system
  run sysctl -w net.ipv4.ip_forward=1
  if [ "$DRY_RUN" != "1" ] && [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
    warn "ip_forward всё ещё не 1! Кто-то перекрывает 90-exam-router.conf. Проверьте:"
    warn "  grep -R 'ip_forward' /etc/sysctl.conf /etc/sysctl.d/ /usr/lib/sysctl.d/ 2>/dev/null"
    warn "  (последним при sysctl --system может читаться /etc/sysctl.conf со значением 0)"
  fi
}

# NAT через nftables + systemd-unit exam-nat (файл перезаписывается целиком)
write_nat() { # write_nat "srcnets через запятую" [файл с prerouting-цепочкой]
  local srcs="$1" dnat_file="${2:-}"
  apt_install nftables
  run mkdir -p /etc/nftables
  {
    printf 'table ip exam_nat {\n chain postrouting {\n  type nat hook postrouting priority srcnat; policy accept;\n  ip saddr { %s } oifname "%s" masquerade\n }\n' "$srcs" "$IF1"
    [ -n "$dnat_file" ] && cat "$dnat_file"
    printf '}\n'
  } | write_file /etc/nftables/exam.nft
  write_file /etc/systemd/system/exam-nat.service <<'EOF'
[Unit]
Description=Exam NAT rules
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/sbin/nft -c -f /etc/nftables/exam.nft
ExecStart=/usr/sbin/nft -f /etc/nftables/exam.nft
ExecStop=/usr/sbin/nft delete table ip exam_nat
[Install]
WantedBy=multi-user.target
EOF
  run systemctl daemon-reload
  svc_enable_now exam-nat
  # enable --now НЕ перезапускает уже работающую службу: без restart модуль 2 (DNAT)
  # не применился бы поверх NAT модуля 1, а повторный запуск дублировал бы правила.
  run systemctl restart exam-nat
  run nft list table ip exam_nat
}

# ---------- пользователи / sudo / ssh ----------
make_user() { # make_user name uid|"" password
  local name="$1" uid="${2:-}" pass="${3:-}"
  if id "$name" >/dev/null 2>&1; then
    ok "пользователь $name уже существует: $(id "$name")"
  else
    if [ -n "$uid" ]; then run useradd -m -u "$uid" -s /bin/bash "$name"
    else run useradd -m -s /bin/bash "$name"; fi
  fi
  if [ -n "$pass" ]; then
    if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] задать пароль пользователю %s\n' "$name"
    else printf '%s:%s\n' "$name" "$pass" | chpasswd && ok "пароль задан: $name"; fi
  else
    warn "Пароль для $name не задан (переменная пуста) — выполните вручную: passwd $name"
  fi
}

sudo_nopasswd() { # sudo_nopasswd name
  local name="$1"
  run mkdir -p /etc/sudoers.d
  printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$name" | write_file "/etc/sudoers.d/$name" 440
  [ "$DRY_RUN" = "1" ] || { chmod 440 "/etc/sudoers.d/$name"; visudo -cf "/etc/sudoers.d/$name"; }
  run control sudo public || warn "control sudo public недоступна"
}

# SSH: порт 2027, только sshuser, MaxAuthTries 2, баннер (модуль 1, п.5)
configure_sshd_exam() {
  apt_install openssh-server sudo
  backup_file /etc/openssh/sshd_config
  printf 'Authorized access only\n' | write_file /etc/openssh/banner
  # В ALT sshd_config может подключать *.conf — правим главный файл и предупреждаем
  local kv key
  for kv in "Port 2027" "AllowUsers sshuser" "MaxAuthTries 2" "Banner /etc/openssh/banner" \
            "PermitRootLogin no" "PasswordAuthentication yes" "PubkeyAuthentication yes"; do
    key="${kv%% *}"
    if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] sshd_config: %s\n' "$kv"; continue; fi
    # OpenSSH берёт ПЕРВОЕ значение: удаляем все старые строки ключа и ставим свою в начало файла
    sed -i -E "/^[#[:space:]]*${key}[[:space:]]/d" /etc/openssh/sshd_config
    sed -i "1i ${kv}" /etc/openssh/sshd_config
    ok "sshd_config: $kv"
  done
  if [ "$DRY_RUN" != "1" ]; then
    grep -R "^Include" /etc/openssh/sshd_config >/dev/null && warn "В sshd_config есть Include — проверьте подключённые файлы на противоречащие директивы"
    /usr/sbin/sshd -t && /usr/sbin/sshd -T | grep -E '^(port|allowusers|maxauthtries|banner|permitrootlogin) '
  fi
  svc_enable_now sshd
  run systemctl restart sshd
  run ss -lntp | grep ':2027' || warn "порт 2027 не слушается — проверьте sshd"
}

# FRR/OSPF: включить ospfd и выполнить vtysh-команды со stdin
frr_ospf() {
  apt_install frr
  if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] ospfd=yes в /etc/frr/daemons + vtysh:\n'; sed 's/^/    | /'; printf '  [dry-run] systemctl enable --now frr\n'; return 0; fi
  backup_file /etc/frr/daemons
  if grep -q '^ospfd=' /etc/frr/daemons; then sed -i 's/^ospfd=.*/ospfd=yes/' /etc/frr/daemons
  else printf 'ospfd=yes\n' >> /etc/frr/daemons; fi
  grep '^ospfd=' /etc/frr/daemons
  systemctl enable --now frr; systemctl restart frr
  vtysh
  vtysh -c 'show ip ospf neighbor' || true
}

mount_additional() {
  run mkdir -p /mnt/additional
  if mountpoint -q /mnt/additional; then ok "Additional.iso уже смонтирован в /mnt/additional"
  elif [ -b /dev/sr0 ]; then run mount -o ro /dev/sr0 /mnt/additional || warn "Не удалось смонтировать /dev/sr0 — подключите Additional.iso в VM"
  else warn "/dev/sr0 не найден — подключите Additional.iso в привод ВМ"; fi
  run find /mnt/additional -maxdepth 3 -type f || true
}

finish() { ok "Готово: $*"; warn "Проверки из материала (ping/dig/curl/ss, перезагрузка ВМ) выполните вручную — см. README и docs/index.html"; }
