#!/usr/bin/env bash
# Установка DEMO2027 из GitHub на Альт Сервер 11.1.
#
# Вариант 1 (одна строка, нужен Интернет и root):
#   su - -c 'curl -fsSL https://raw.githubusercontent.com/TeSIX/demo2027virtualmachine-/main/install.sh | bash'
#
# Вариант 2 (вручную):
#   su -
#   apt-get update && apt-get install -y git
#   git clone https://github.com/TeSIX/demo2027virtualmachine-.git /opt/demo2027
#   cd /opt/demo2027 && cp config.env.example config.env && nano config.env
#   ./demo2027.sh hq-srv 1 --yes
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/TeSIX/demo2027virtualmachine-.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/demo2027}"

[ "$(id -u)" = "0" ] || { echo "Нужен root: su -" >&2; exit 1; }

if ! command -v git >/dev/null 2>&1; then
  echo ">> Устанавливаю git через apt-get…"
  apt-get update
  apt-get install -y git ca-certificates curl
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  echo ">> Обновляю $INSTALL_DIR…"
  git -C "$INSTALL_DIR" fetch origin
  git -C "$INSTALL_DIR" checkout "$REPO_BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$REPO_BRANCH"
else
  echo ">> Клонирую $REPO_URL -> $INSTALL_DIR…"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR"/demo2027.sh "$INSTALL_DIR"/install.sh \
         "$INSTALL_DIR"/scripts/m1/*.sh "$INSTALL_DIR"/scripts/m2/*.sh \
         "$INSTALL_DIR"/scripts/m3/*.sh "$INSTALL_DIR"/tools/*.sh 2>/dev/null || true

[ -f "$INSTALL_DIR/config.env" ] || cp "$INSTALL_DIR/config.env.example" "$INSTALL_DIR/config.env"

cat <<EOF

Готово. Дальше:
  cd $INSTALL_DIR
  nano config.env                 # пароли, MAC HQ-CLI, диски RAID, часовой пояс
  ./demo2027.sh --list            # список ролей и модулей
  ./demo2027.sh hq-srv 1 --dry-run   # сначала посмотреть, что будет сделано
  ./demo2027.sh hq-srv 1 --yes       # выполнить модуль 1 для роли hq-srv

Порядок: модуль 1 по всем ВМ -> модуль 2 -> модуль 3 (см. README.md).
EOF
