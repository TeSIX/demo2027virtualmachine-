#!/usr/bin/env bash
# Модуль 3 · ISP: reverse proxy Apache (web->HQ-SRV, docker->BR-SRV), Basic Auth WEB,
# HTTPS с сертификатом с HQ-SRV (30 дней, SAN web+docker). Требуются DNAT модуля 2.
step "M3 · ISP: Apache reverse proxy"
apt_install apache2
run a2enmod proxy
run a2enmod proxy_http
run a2enmod auth_basic
run a2enmod authn_file
run a2enmod ssl
run a2enmod headers
run curl -s -o /dev/null -w 'backend HQ %{http_code}\n' http://172.16.1.2:8080/ || warn "Backend HQ 172.16.1.2:8080 не отвечает (DNAT модуля 2?)"
run curl -s -o /dev/null -w 'backend BR %{http_code}\n' http://172.16.2.2:8080/ || warn "Backend BR 172.16.2.2:8080 не отвечает (DNAT модуля 2?)"

step "M3 · ISP: htpasswd WEB"
if [ "$DRY_RUN" = "1" ]; then
  printf '  [dry-run] htpasswd -cb /etc/httpd2/conf/web.htpasswd WEB ***\n'
elif [ ! -f /etc/httpd2/conf/web.htpasswd ]; then
  htpasswd -cbB /etc/httpd2/conf/web.htpasswd WEB "${WEB_HTPASSWD_PASSWORD:-P@ssw0rd}" 2>/dev/null \
    || htpasswd -cb /etc/httpd2/conf/web.htpasswd WEB "${WEB_HTPASSWD_PASSWORD:-P@ssw0rd}"
  chown root:apache2 /etc/httpd2/conf/web.htpasswd 2>/dev/null || chown root:apache /etc/httpd2/conf/web.htpasswd || true
  chmod 640 /etc/httpd2/conf/web.htpasswd
else ok "web.htpasswd уже есть — не пересоздаю (-c стёр бы пользователей)"; fi

step "M3 · ISP: сертификат с HQ-SRV (если ещё не получен)"
run mkdir -p /etc/httpd2/ssl
if [ "$DRY_RUN" != "1" ] && [ ! -f /etc/httpd2/ssl/sites.crt ]; then
  scp -P 2027 "sshuser@172.16.1.2:/home/sshuser/sites.key" /etc/httpd2/ssl/ \
    && scp -P 2027 "sshuser@172.16.1.2:/home/sshuser/sites.crt" /etc/httpd2/ssl/ \
    && chmod 600 /etc/httpd2/ssl/sites.key \
    || warn "Не удалось забрать сертификат: сначала выполните m3 на hq-srv (он положит sites.* в /home/sshuser)"
fi
[ -f /etc/httpd2/ssl/sites.crt ] || warn "Нет /etc/httpd2/ssl/sites.crt — HTTPS-виртуалхосты ниже не заработают, пока не выполните m3 hq-srv"

write_file /etc/httpd2/conf/sites-available/reverse.conf <<EOF
<VirtualHost *:80>
    ServerName web.${DOMAIN}
    Redirect permanent / https://web.${DOMAIN}/
</VirtualHost>
<VirtualHost *:80>
    ServerName docker.${DOMAIN}
    Redirect permanent / https://docker.${DOMAIN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName web.${DOMAIN}
    SSLEngine on
    SSLCertificateFile /etc/httpd2/ssl/sites.crt
    SSLCertificateKeyFile /etc/httpd2/ssl/sites.key
    ProxyRequests Off
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    ProxyPass / http://172.16.1.2:8080/
    ProxyPassReverse / http://172.16.1.2:8080/
    <Location />
        AuthType Basic
        AuthName "WEB"
        AuthBasicProvider file
        AuthUserFile /etc/httpd2/conf/web.htpasswd
        Require user WEB
    </Location>
</VirtualHost>

<VirtualHost *:443>
    ServerName docker.${DOMAIN}
    SSLEngine on
    SSLCertificateFile /etc/httpd2/ssl/sites.crt
    SSLCertificateKeyFile /etc/httpd2/ssl/sites.key
    ProxyRequests Off
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    ProxyPass / http://172.16.2.2:8080/
    ProxyPassReverse / http://172.16.2.2:8080/
</VirtualHost>
EOF
if [ "$DRY_RUN" != "1" ]; then
  grep -Rlq '^[[:space:]]*Listen 443' /etc/httpd2/conf/ 2>/dev/null || warn "Проверьте Listen 443 в /etc/httpd2/conf после включения mod_ssl"
  a2ensite reverse 2>/dev/null || a2ensite reverse.conf 2>/dev/null || warn "a2ensite reverse не удался"
  (apachectl -t 2>/dev/null || apache2ctl -t) && systemctl enable --now httpd2 && systemctl reload httpd2
  ss -lntp | grep ':443' || warn "443 не слушается"
  curl -s -o /dev/null -w 'web без пароля: %{http_code} (ожидается 401)\n' -H "Host: web.${DOMAIN}" http://172.16.2.1/ || true
  warn "Итоговая HTTPS-проверка — с HQ-CLI после импорта CA: curl -u WEB https://web.${DOMAIN}/"
fi
finish "ISP (модуль 3)"
