#!/usr/bin/env bash
# Модуль 3 · BR-SRV: импорт users.csv в au-team.irpo + Ansible playbook PC-INFO.
step "M3 · BR-SRV: импорт пользователей из users.csv"
mount_additional
run mkdir -p /root/domain-import
CSV_SRC="$(find /mnt/additional -name users.csv -print -quit 2>/dev/null || true)"
if [ -n "$CSV_SRC" ]; then run cp "$CSV_SRC" /root/domain-import/users.csv
else warn "users.csv на Additional.iso не найден — положите его в /root/domain-import/users.csv"; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f /root/domain-import/users.csv ]; then
  run bash "$SCRIPT_DIR/tools/import-users.sh" /root/domain-import/users.csv
else warn "Импорт пропущен: нет /root/domain-import/users.csv"; fi
warn "На HQ-CLI проверьте: id '<логин_из_csv>@${DOMAIN}' и вход пользователя в GNOME"

step "M3 · BR-SRV: Ansible PC-INFO (HQ-SRV + HQ-CLI -> YAML на BR-SRV)"
write_file /etc/ansible/pc-info.yml <<'EOF'
---
- name: Collect HQ machine information
  hosts: servers
  gather_facts: true
  become: true
  tasks:
    - name: Create reports directory on controller
      ansible.builtin.file:
        path: /etc/ansible/PC-INFO
        state: directory
        mode: '0755'
      delegate_to: localhost
      run_once: true

    - name: Save host name and IPv4 addresses on controller
      ansible.builtin.copy:
        dest: "/etc/ansible/PC-INFO/{{ inventory_hostname }}.yml"
        mode: '0644'
        content: "{{ {'hostname': ansible_facts['hostname'], 'fqdn': ansible_facts['fqdn'], 'ipv4': ansible_facts['all_ipv4_addresses']} | to_nice_yaml }}"
      delegate_to: localhost
EOF
if [ "$DRY_RUN" != "1" ]; then
  (cd /etc/ansible && ansible-playbook pc-info.yml --syntax-check && ansible-playbook pc-info.yml \
    && ls -l /etc/ansible/PC-INFO) || warn "playbook не выполнился — сначала модуль 2 (ключи SSH, инвентарь, 4 pong)"
fi
finish "BR-SRV (модуль 3)"
