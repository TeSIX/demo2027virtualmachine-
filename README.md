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

На каждой виртуальной машине (Альт Сервер 11.1), от root:

```bash
su -
curl -fsSL https://raw.githubusercontent.com/TeSIX/demo2027virtualmachine-/main/install.sh | bash
```

или вручную:

```bash
su -
apt-get update && apt-get install -y git
git clone https://github.com/TeSIX/demo2027virtualmachine-.git /opt/demo2027
cd /opt/demo2027
```

`install.sh` ставит git (если нет), клонирует/обновляет репозиторий в `/opt/demo2027`
и создаёт `config.env` из примера.

## Настройка и запуск

```bash
cd /opt/demo2027
cp config.env.example config.env   # если ещё нет
nano config.env                    # пароли, HQ_CLI_MAC, RAID_DISKS, TIMEZONE...

./demo2027.sh --list               # роли и модули
./demo2027.sh hq-rtr 1 --dry-run   # ПОКАЗАТЬ, что будет сделано (ничего не меняет)
./demo2027.sh hq-rtr 1 --yes       # выполнить
```

Формат: `./demo2027.sh <роль> <модуль|all> [--yes] [--dry-run]`
Роли: `isp hq-rtr br-rtr br-fw hq-srv br-srv hq-cli hq-sw`

### Порядок выполнения

1. **Модуль 1** — по всем ВМ: `isp → hq-rtr → br-rtr → br-fw → hq-srv → br-srv → hq-cli`
   (и `hq-sw`, только если коммутатор — отдельная Linux-ВМ, а не гипервизор).
2. **Модуль 2** — `isp → hq-srv → br-srv → hq-cli → hq-rtr → br-rtr`
   (на BR-SRV Samba DC уже должен работать — provision скрипты не делают).
3. **Модуль 3** — `br-srv → hq-srv → isp → hq-cli`
   (сертификат создаётся на HQ-SRV, потом ISP забирает его по SCP, потом HQ-CLI импортирует CA).

Перед модулями 2–3 подключите **Additional.iso** в привод нужных ВМ
(скрипты сами смонтируют `/dev/sr0` в `/mnt/additional`).

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

## Проверка скриптов

```bash
bash -n demo2027.sh install.sh scripts/lib/common.sh scripts/m*/*.sh tools/*.sh
./demo2027.sh hq-srv 1 --dry-run   # на ALT-ВМ под root
```
