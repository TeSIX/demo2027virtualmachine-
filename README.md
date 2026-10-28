# DEMO2027 · Скрипты для Альт Сервер 11.1 (КИМ 09.02.06-1-2027)

Автоматизация практического курса из [`docs/index.html`](docs/index.html) (три модуля ГИА):
ручные команды из материала превращены в идемпотентные bash-скрипты под **ALT Linux**
(Альт Сервер 11.1, сеть — **etcnet**, интерфейсы `ens33/ens37/ens38`), с установкой из GitHub.

| Модуль | Что настраивается |
|---|---|
| **1. Сетевая инфраструктура** | адресация etcnet, VLAN 100/200/999, forwarding, NAT (nftables), пользователи `sshuser`/`net_admin`, SSH порт 2027, GRE HQ↔BR, OSPF+MD5 (FRR), DHCP, DNS (dnsmasq) |
| **2. Сетевое администрирование** | Samba DC: группа `hq`, `hquser1..5`; ввод HQ-CLI в домен; RAID 0 → `/raid`; NFS; chrony (ISP — stratum 5); Ansible (4 pong); Docker `testapp` :8080; Apache+PHP+MariaDB (`webdb`); DNAT; Яндекс Браузер |
| **3. Эксплуатация** | импорт `users.csv` в AD; reverse proxy на ISP; WEB-аутентификация; сертификат на 30 дней + доверие HQ-CLI; atop 420 с; CUPS-PDF; Ansible PC-INFO; fail2ban SSH (3/60 с); бэкап restic → репозиторий `irpo` |

## Установка из GitHub

> ⚠️ **Скрипты лежат НЕ в `main`, а в ветке `arena/e8a8a3cf-demo2027virtualmachine`** (PR #1).
> В `main` сейчас только начальный коммит — установка «с main» не сработает.
> Все команды ниже сразу берут ветку со скриптами.
>
> Команды выполняются **на каждой виртуальной машине** (Альт Сервер 11.1) из консоли
> гипервизора, под root. Нужен доступ ВМ в Интернет (для `git clone` и `apt-get`).

### Способ 1 — через git (надёжный, работает сейчас)

```bash
su -
apt-get update && apt-get install -y git ca-certificates
git clone -b arena/e8a8a3cf-demo2027virtualmachine \
  https://github.com/TeSIX/demo2027virtualmachine-.git /opt/demo2027
cd /opt/demo2027
./install.sh        # выставит права, создаст config.env, подскажет дальнейшие шаги
```

### Способ 2 — одной командой (если на ВМ уже есть curl)

```bash
su -
curl -f -s -S -L https://raw.githubusercontent.com/TeSIX/demo2027virtualmachine-/arena/e8a8a3cf-demo2027virtualmachine/install.sh | bash
```

> ⚠️ Не путайте `-f` и `-F`: нужна **маленькая** `f` (`--fail`). Команда вида
> `curl -FsSL …` даст ошибку `Warning: Illegally formatted input field!` /
> `curl: option -FsSL: is badly used here` — это значит, что введена большая `F`
> (`--form`, загрузка файлов), а не то, что ветка или адрес недоступны.

`install.sh` по умолчанию клонирует именно ветку `arena/e8a8a3cf-demo2027virtualmachine`.
Если когда-нибудь PR #1 сольют в `main`, установка с `main` включается переменной:
`REPO_BRANCH=main bash install.sh`.

`install.sh` сам ставит git (если нет), клонирует/обновляет репозиторий в `/opt/demo2027`,
выставляет права на исполнение и создаёт `config.env` из примера.

### Обновление уже установленной копии

```bash
su -
cd /opt/demo2027
git pull --ff-only
```

или повторно запустите способ 1 — `install.sh` сам выполнит обновление (`git pull`).

## Настройка и запуск

```bash
cd /opt/demo2027
cp config.env.example config.env   # если install.sh ещё не создал его
nano config.env                    # пароли, HQ_CLI_MAC, RAID_DISKS, TIMEZONE...

./demo2027.sh --list               # роли и модули
./demo2027.sh hq-rtr 1 --dry-run   # ПОКАЗАТЬ, что будет сделано (ничего не меняет)
./demo2027.sh hq-rtr 1 --yes       # выполнить
```

Формат: `./demo2027.sh <роль> <модуль|all> [--yes] [--dry-run]`
Роли: `isp hq-rtr br-rtr br-fw hq-srv br-srv hq-cli hq-sw`

> ⚠️ Запускать нужно именно `demo2027.sh`, а не файлы из `scripts/m1|m2|m3/`:
> это фрагменты, все их функции (`step`, `eth_iface`, `apt_install`…) определены
> в `scripts/lib/common.sh`, который подключает только диспетчер. Прямой запуск
> вида `bash scripts/m1/hq-rtr.sh` раньше давал `command not found` на каждой
> строке; теперь фрагменты сами перенаправляют такой запуск в `demo2027.sh`
> (роль и модуль подставляются по имени файла), но основной путь — диспетчер.

### Команды по виртуальным машинам (порядок выполнения)

Сначала модуль 1 на всех ВМ, затем модуль 2, затем модуль 3.
На каждой ВМ — свой роль-аргумент:

```bash
# --- Модуль 1: сетевая инфраструктура ---
./demo2027.sh isp    1 --yes     # на ВМ ISP
./demo2027.sh hq-rtr 1 --yes     # на ВМ HQ-RTR
./demo2027.sh br-rtr 1 --yes     # на ВМ BR-RTR
./demo2027.sh br-fw  1 --yes     # на ВМ BR-FW
./demo2027.sh hq-srv 1 --yes     # на ВМ HQ-SRV
./demo2027.sh br-srv 1 --yes     # на ВМ BR-SRV
./demo2027.sh hq-cli 1 --yes     # на ВМ HQ-CLI
./demo2027.sh hq-sw  1 --yes     # только если HQ-SW — отдельная Linux-ВМ

# --- Модуль 2: сетевое администрирование (Samba DC на BR-SRV уже работает) ---
./demo2027.sh isp    2 --yes
./demo2027.sh hq-srv 2 --yes
./demo2027.sh br-srv 2 --yes
./demo2027.sh hq-cli 2 --yes
./demo2027.sh hq-rtr 2 --yes
./demo2027.sh br-rtr 2 --yes

# --- Модуль 3: эксплуатация ---
./demo2027.sh br-srv 3 --yes
./demo2027.sh hq-srv 3 --yes
./demo2027.sh isp    3 --yes
./demo2027.sh hq-cli 3 --yes
```

> Перед каждым `--yes` рекомендуется тот же запуск с `--dry-run`.
> Перед модулями 2–3 подключите **Additional.iso** в привод нужных ВМ
> (скрипты сами смонтируют `/dev/sr0` в `/mnt/additional`).

### Удаление

```bash
su -
rm -rf /opt/demo2027
# Конфиги, созданные скриптами, при этом НЕ откатываются.
# Резервные копии изменённых файлов лежат в /root/demo2027-backup/<дата-время>/ —
# восстановите нужные файлы из них вручную.
```

### Если отдельной HQ-SW нет (VMware Workstation)

Workstation сама VLAN access/trunk не настраивает — нужен Linux-мост:

1. Создайте лёгкую ВМ **HQ-SW** (Альт Сервер 11.1, без графики, 1 CPU / 1 ГБ / 10 ГБ)
   с **четырьмя** адаптерами: три — в LAN-сегменты `HQ-TRUNK`, `HQ-SRV`, `HQ-CLI`
   (создаются кнопкой LAN Segments в настройках адаптера), четвёртый — NAT,
   временно, чтобы поставить скрипты.
2. Переключите существующие ВМ: HQ-RTR адаптер 2 → `HQ-TRUNK` (+ адаптер 1 HQ-SW),
   HQ-SRV → `HQ-SRV` (+ адаптер 2 HQ-SW), HQ-CLI → `HQ-CLI` (+ адаптер 3 HQ-SW).
   **Нельзя** держать HQ-SRV в одном сегменте с первым адаптером HQ-RTR.
3. На HQ-SW проверьте порядок: `./demo2027.sh hq-sw 1 --dry-run | grep Интерфейсы`
   (IF1/IF2/IF3 = trunk/сервер/клиент; NAT должен быть четвёртым, IF4 не используется),
   затем `./demo2027.sh hq-sw 1 --yes`.
4. Проверьте с HQ-RTR `ping 192.168.100.2`, на HQ-SRV шлюз должен иметь MAC
   второго адаптера HQ-RTR. После этого NAT-адаптер у HQ-SW можно удалить и
   перезагрузить её — управление останется через `192.168.99.2` (VLAN 999).

## Что важно знать

- **`--dry-run` сначала.** Скрипты перезаписывают конфиги, но перед каждой записью делают
  резервную копию в `/root/demo2027-backup/<дата-время>/…`.
- **Сеть применяется сразу** (`systemctl restart network`) — при смене адреса SSH разорвётся,
  работайте из консоли гипервизора.
- **Пароли** берутся из `config.env` (по умолчанию учебные `P@ssw0rd`, как в материале).
  `config.env` в git не попадает (`.gitignore`).
- **Разрушающие операции защищены:** RAID создаётся только при `RAID_CONFIRM=YES`
  и явном подтверждении; ввод HQ-CLI в домен — только при заданном `DOMAIN_ADMIN_PASSWORD`.
- **Вручную остаются** (скрипт подскажет в конце): `ssh-copy-id` для Ansible,
  проверка отпечатка CA, вход доменного пользователя в GNOME, тестовая печать,
  перезагрузка ВМ и итоговые проверки из материала.
- **Имена адаптеров определяются автоматически**: материал называет их
  ens33/ens37/ens38, но гипервизор может дать другие (например, `ens34` вместо
  ens37). Скрипты берут 1-й, 2-й и 3-й физический интерфейс по порядку; при
  неверном порядке задайте `IFACE1/IFACE2/IFACE3` в `config.env`.
- Адреса, VLAN, OSPF MD5-пароль, пул DHCP и записи DNS — точно как в исходном материале;
  меняется всё через `config.env` и правкой скриптов в `scripts/m1|m2|m3/<роль>.sh`.

## Структура

```
install.sh              установка из GitHub одной командой
demo2027.sh             точка входа: <роль> <модуль> [--yes] [--dry-run]
config.env.example      все переменные стенда (пароли, MAC, диски, TZ)
scripts/lib/common.sh   общие функции: etcnet, NAT, sshd, FRR, backup, dry-run
scripts/m1/<роль>.sh    модуль 1 по ролям ВМ
scripts/m2/<роль>.sh    модуль 2 по ролям ВМ
scripts/m3/<роль>.sh    модуль 3 по ролям ВМ
tools/import-users.sh   импорт users.csv -> OU + пользователи Samba AD (идемпотентный)
docs/index.html         исходный материал курса (все три модуля)
```

## Известные ошибки и риски

Перед боевым запуском посмотрите [`AUDIT.md`](AUDIT.md) — аудит скриптов:
исправленные критичные дефекты (импорт CSV, порядок запуска dnsmasq, DNAT,
автоперазагрузка HQ-CLI и др.) и риски, которые зависят от стенда
(RAID, DNS-пересылка для домена, пакеты ALT p11, fail2ban, CUPS).

## Проверка скриптов

```bash
bash -n demo2027.sh install.sh scripts/lib/common.sh scripts/m*/*.sh tools/*.sh
./demo2027.sh hq-srv 1 --dry-run   # на ALT-ВМ под root
```
