#!/usr/bin/env bash
# Модуль 2 · BR-SRV: политика паролей Samba DC, группа hq + hquser1..5,
# Ansible (инвентарь 4 узлов, ключ, pong), подготовка testapp вынесена в m2 docker-часть ниже.
# Samba DC уже развёрнут на стенде: provision НЕ выполняем.
step "M2 · BR-SRV: chrony <- ISP 172.16.2.1"
apt_install chrony
backup_file /etc/chrony.conf
write_file /etc/chrony.conf <<'EOF'
server 172.16.2.1 iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF
svc_enable_now chronyd
run systemctl restart chronyd
run chronyc tracking || true

step "M2 · BR-SRV: проверка Samba DC"
run testparm -s || warn "testparm не прошёл — проверьте Samba DC"
run samba-tool domain info 127.0.0.1 || warn "samba-tool domain info не отвечает"

step "M2 · BR-SRV: политика паролей и группа hq"
if [ "$DRY_RUN" = "1" ]; then
  printf '  [dry-run] samba-tool domain passwordsettings set --min-pwd-length=8 --account-lockout-threshold=5\n'
  printf '  [dry-run] samba-tool group add hq; создать hquser1..hquser5 и добавить в hq\n'
else
  samba-tool domain passwordsettings set --min-pwd-length=8 --account-lockout-threshold=5
  samba-tool group show hq >/dev/null 2>&1 || samba-tool group add hq
  for i in 1 2 3 4 5; do
    samba-tool user show "hquser$i" >/dev/null 2>&1 || samba-tool user create "hquser$i" "${DOMAIN_USER_PASSWORD:-P@ssw0rd}"
    samba-tool group addmembers hq "hquser$i" || true
  done
  samba-tool group listmembers hq
  samba-tool domain passwordsettings show
fi

step "M2 · BR-SRV: Ansible"
apt_install ansible openssh-clients python3
run mkdir -p /etc/ansible /root/.ssh
[ "$DRY_RUN" = "1" ] || chmod 700 /root/.ssh
if [ ! -f /root/.ssh/id_ed25519 ]; then
  run ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ''
else ok "Ключ /root/.ssh/id_ed25519 уже есть — не перезаписываю"; fi
write_file /etc/ansible/inventory.ini <<EOF
[servers]
hq-srv ansible_host=192.168.100.2 ansible_user=sshuser ansible_port=2027
hq-cli ansible_host=192.168.200.2 ansible_user=sshuser ansible_port=22

[routers]
hq-rtr ansible_host=172.16.1.2 ansible_user=net_admin ansible_port=22
br-rtr ansible_host=172.16.2.2 ansible_user=net_admin ansible_port=22

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become=true
ansible_become_method=sudo
EOF
write_file /etc/ansible/ansible.cfg <<'EOF'
[defaults]
inventory = /etc/ansible/inventory.ini
host_key_checking = True
interpreter_python = /usr/bin/python3
EOF
cat <<'EOF'
ВРУЧНУЮ (нужны пароли sshuser/net_admin, проверка отпечатков host key):
  ssh-copy-id -p 2027 sshuser@192.168.100.2
  ssh-copy-id -p 22   sshuser@192.168.200.2
  ssh-copy-id -p 22   net_admin@172.16.1.2
  ssh-copy-id -p 22   net_admin@172.16.2.2
  cd /etc/ansible && ansible all -m ping      # ожидаются 4 x pong
EOF
[ "$DRY_RUN" = "1" ] || (cd /etc/ansible && ansible-inventory --list || true)

step "M2 · BR-SRV: Docker testapp (образы и compose — с Additional.iso)"
mount_additional
apt_install docker-engine
if [ "$DRY_RUN" != "1" ]; then
  (apt-get install -y docker-compose-v2 2>/dev/null || apt-get install -y docker-compose 2>/dev/null) \
    || warn "Compose не установился — проверьте имя пакета: apt-cache search docker-compose"
  docker compose version || docker-compose version || warn "docker compose недоступен"
fi
svc_enable_now docker
run mkdir -p /opt/testapp
if [ "$DRY_RUN" != "1" ]; then
  if [ -d /mnt/additional/docker ]; then
    for img in /mnt/additional/docker/*; do [ -f "$img" ] && docker load -i "$img"; done
    docker image ls
  else warn "Каталог /mnt/additional/docker не найден — загрузите образы вручную: docker load -i <архив>"; fi
  found="$(find /mnt/additional -maxdepth 3 -name 'compose.y*ml' -print -quit 2>/dev/null)"
  if [ -n "$found" ]; then cp -a "$(dirname "$found")/." /opt/testapp/; ok "compose скопирован из $found в /opt/testapp"
  else warn "compose.yaml на ISO не найден — скопируйте выданный compose в /opt/testapp вручную"; fi
  if [ -f /opt/testapp/compose.yaml ] || [ -f /opt/testapp/compose.yml ]; then
    (cd /opt/testapp && (docker compose config && docker compose up -d && docker compose ps) \
      || warn "docker compose up не удался — проверьте image:/порты (нужен 8080 на хосте) и логи: docker compose logs")
    curl -I http://127.0.0.1:8080/ || warn "testapp на 127.0.0.1:8080 не отвечает"
  fi
fi
finish "BR-SRV (модуль 2)"
