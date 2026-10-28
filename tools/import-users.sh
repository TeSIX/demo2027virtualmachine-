#!/usr/bin/env bash
# Массовый импорт пользователей Samba AD из users.csv (модуль 3, п.1).
# Запуск на BR-SRV:  ./tools/import-users.sh /root/domain-import/users.csv
#
# Ожидаемые колонки CSV (заголовок обязателен, разделитель ',' или ';' — определяется сам):
#   login,password,given_name,surname,ou
# Пример строки:  ivanov,P@ssw0rd,Иван,Иванов,OfficeHQ
# ou — имя подразделения; вложенность через '/': OfficeHQ/Отдел продаж
# Идемпотентно: существующие OU/пользователи не дублируются.
set -euo pipefail
CSV="${1:?Использование: $0 <users.csv>}"
DOMAIN_DC="DC=au-team,DC=irpo"
[ "$(id -u)" = 0 ] || { echo "Нужен root" >&2; exit 1; }
[ -f "$CSV" ] || { echo "Нет файла $CSV" >&2; exit 1; }
command -v samba-tool >/dev/null || { echo "samba-tool не найден — запускайте на BR-SRV (Samba DC)" >&2; exit 1; }

header="$(head -n1 "$CSV" | sed -e "1s/^\xEF\xBB\xBF//" -e 's/\r$//' -e 's/[[:space:]]*,[[:space:]]*/,/g' -e 's/[[:space:]]*;[[:space:]]*/;/g')"
case "$header" in *";"*) DELIM=';' ;; *) DELIM=',' ;; esac
echo "Файл: $CSV · разделитель: '$DELIM' · заголовок: $header"
echo "$header" | tr "$DELIM" '\n' | grep -qi '^login$' \
  || { echo "В заголовке нет колонки login. Скрипт ждёт: login,password,given_name,surname,ou" >&2
       echo "Если у выданного users.csv другие колонки — поправьте номера полей ниже под его заголовок." >&2; exit 1; }

# номера колонок по заголовку
col() { echo "$header" | tr "$DELIM" '\n' | grep -n -ix "$1" | cut -d: -f1; }
C_LOGIN="$(col login)"; C_PASS="$(col password)"; C_GN="$(col given_name)"; C_SN="$(col surname)"; C_OU="$(col ou)"
for v in C_LOGIN C_PASS C_OU; do [ -n "${!v}" ] || { echo "Не найдена обязательная колонка ($v)" >&2; exit 1; }; done

ensure_ou() { # ensure_ou OfficeHQ/Отдел -> создаёт цепочку, печатает относительный --userou
  local rel="" part dn
  IFS='/' read -ra parts <<< "$1"
  for part in "${parts[@]}"; do
    dn="OU=${part}${rel:+,$rel},$DOMAIN_DC"
    # ВАЖНО: stdout samba-tool нельзя выпускать наружу функции — он попадёт в $(ensure_ou)
    # и испортит --userou ("Created OU ...OU=..."). Всё диагностическое — в stderr.
    if samba-tool ou list 2>/dev/null | grep -qx "$dn"; then echo "OU есть: $dn" >&2
    else samba-tool ou create "$dn" >&2; fi
    rel="OU=${part}${rel:+,$rel}"
  done
  printf '%s' "$rel"
}

CREATED=0; FAILED=0
# || [ ${#F[@]} -gt 0 ] — иначе последняя строка CSV без завершающего \n теряется
while IFS="$DELIM" read -r -a F || [ "${#F[@]}" -gt 0 ]; do
  get() { local n="${!1:-}"; [ -n "$n" ] && printf '%s' "${F[$((n-1))]:-}" | tr -d '\r' || true; }
  login="$(get C_LOGIN)"; pass="$(get C_PASS)"; gn="$(get C_GN)"; sn="$(get C_SN)"; ou="$(get C_OU)"
  [ -n "$login" ] || continue
  [ -n "$pass" ] || { echo "ПРОПУСК $login: пустой пароль"; continue; }
  if [ -n "$ou" ]; then
    userou="$(ensure_ou "$ou")"
    args=(user create "$login" "$pass" --userou="$userou")
    where="$userou,$DOMAIN_DC"
  else
    # OU не указана — НЕ создаём фиктивную OU=Users, пользователь попадёт в CN=Users
    args=(user create "$login" "$pass")
    where="CN=Users,$DOMAIN_DC"
  fi
  if samba-tool user show "$login" >/dev/null 2>&1; then
    echo "ПРОПУСК $login: уже существует"
  else
    [ -n "$gn" ] && args+=(--given-name="$gn")
    [ -n "$sn" ] && args+=(--surname="$sn")
    if samba-tool "${args[@]}"; then echo "СОЗДАН: $login ($where)"; CREATED=$((CREATED+1))
    else echo "ОШИБКА создания: $login" >&2; FAILED=$((FAILED+1)); fi
  fi
done < <(tail -n +2 "$CSV")
echo "Итого: создано=$CREATED, ошибок=$FAILED"
[ "$FAILED" = "0" ] || exit 1
echo "--- Проверка ---"
samba-tool ou list
samba-tool user list
