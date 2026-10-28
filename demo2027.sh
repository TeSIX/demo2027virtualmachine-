#!/usr/bin/env bash
# DEMO2027 — автоматизация КИМ 09.02.06-1-2027 (Альт Сервер 11.1) по ролям ВМ.
#
# Использование:
#   ./demo2027.sh <роль> <модуль> [--yes] [--dry-run]
#   ./demo2027.sh <роль> all      [--yes] [--dry-run]
#   ./demo2027.sh --list
#
# Роли:    isp hq-rtr br-rtr br-fw hq-srv br-srv hq-cli hq-sw
# Модули:  1 (сеть), 2 (администрирование), 3 (эксплуатация), all
# Примеры:
#   ./demo2027.sh hq-rtr 1 --dry-run
#   ./demo2027.sh hq-srv 2 --yes
#   su - -c '/opt/demo2027/demo2027.sh br-srv 1 --yes'
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

usage() {
  sed -n '2,20p' "$0"
  echo; echo "Роли/модули:"; ./demo2027.sh --list 2>/dev/null || true
}

list_all() {
  cat <<'EOF'
Роли ВМ:  isp | hq-rtr | br-rtr | br-fw | hq-srv | br-srv | hq-cli | hq-sw

Модуль 1 (scripts/m1/): isp hq-rtr br-rtr br-fw hq-srv br-srv hq-cli hq-sw
  адресация etcnet, VLAN/GRE, forwarding, NAT, пользователи, SSH 2027, OSPF+MD5, DHCP, DNS
Модуль 2 (scripts/m2/): br-srv hq-srv hq-cli isp hq-rtr br-rtr
  Samba DC/пользователи, ввод HQ-CLI в домен, RAID0, NFS, chrony, Ansible, Docker testapp,
  Apache+PHP+MariaDB, DNAT, Яндекс Браузер
Модуль 3 (scripts/m3/): br-srv isp hq-srv hq-cli
  импорт users.csv, reverse proxy, WEB-аутентификация, сертификат 30 дней, atop 420с,
  CUPS-PDF, Ansible PC-INFO, fail2ban SSH, бэкап restic irpo
EOF
}

[ "${1:-}" = "--list" ] && { list_all; exit 0; }
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -lt 2 ] && { usage; exit 0; }

ROLE="$1"; MODULE="$2"; shift 2
export DEMO2027_DISPATCHED=1   # маркер для фрагментов scripts/m*/: «мы запущены через диспетчер»
export ASSUME_YES=0 DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --yes|-y) export ASSUME_YES=1 ;;
    --dry-run) export DRY_RUN=1 ;;
    *) echo "Неизвестный параметр: $a" >&2; exit 2 ;;
  esac
done

case "$ROLE" in isp|hq-rtr|br-rtr|br-fw|hq-srv|br-srv|hq-cli|hq-sw) : ;;
  *) echo "Неизвестная роль: $ROLE" >&2; list_all; exit 2 ;; esac

# shellcheck source=config.env.example
[ -f "$ROOT/config.env" ] && { set -a; . "$ROOT/config.env"; set +a; } \
  || echo "ВНИМАНИЕ: config.env не найден — используются значения по умолчанию из config.env.example" >&2
: "${DOMAIN:=au-team.irpo}" "${TIMEZONE:=Asia/Irkutsk}"
export DOMAIN TIMEZONE

# shellcheck source=scripts/lib/common.sh
. "$ROOT/scripts/lib/common.sh"
need_root "$@"

run_module() { # run_module 1
  local m="$1"
  local f="$ROOT/scripts/m$m/$ROLE.sh"
  if [ ! -f "$f" ]; then warn "Для роли $ROLE модуля $m нет скрипта ($f) — пропускаю"; return 0; fi
  step "Роль $ROLE · модуль $m · $f"
  ( . "$ROOT/scripts/lib/common.sh"; . "$f" )
}

case "$MODULE" in
  1|2|3) run_module "$MODULE" ;;
  all)   run_module 1; run_module 2; run_module 3 ;;
  *) echo "Модуль должен быть 1, 2, 3 или all" >&2; exit 2 ;;
esac
