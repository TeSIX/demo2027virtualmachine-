#!/usr/bin/env bash
# Установка DEMO2027 из GitHub на Альт Сервер 11.1.
#
# Скрипты лежат в ветке arena/e8a8a3cf-demo2027virtualmachine (PR #1), в main их пока нет!
# Поэтому установщик по умолчанию берёт именно эту ветку.
#
# Вариант 1 (надёжный, нужен Интернет и root):
#   su -
#   apt-get update && apt-get install -y git
#   git clone -b arena/e8a8a3cf-demo2027virtualmachine \
#     https://github.com/TeSIX/demo2027virtualmachine-.git /opt/demo2027
#   cd /opt/demo2027 && ./install.sh
#
# Вариант 2 (одной строкой, если на ВМ уже есть curl):
#   su - -c 'curl -f -s -S -L https://raw.githubusercontent.com/TeSIX/demo2027virtualmachine-/arena/e8a8a3cf-demo2027virtualmachine/install.sh | bash'
#   (флаг — маленькая -f, не -F: с большой F curl выдаст 'option -FsSL: is badly used here')
#
# Если позже PR #1 сольют в main, установку с main включайте так:
#   REPO_BRANCH=main bash install.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/TeSIX/demo2027virtualmachine-.git}"
REPO_BRANCH="${REPO_BRANCH:-arena/e8a8a3cf-demo2027virtualmachine}"
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
