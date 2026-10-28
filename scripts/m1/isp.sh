#!/usr/bin/env bash
# Модуль 1 · ISP: ens33=DHCP(Интернет), ens37=172.16.1.1/28 (к HQ), ens38=172.16.2.1/28 (к BR),
# forwarding + NAT офисных трансляций. Выполняется из demo2027.sh.
step "M1 · ISP: имя, время, адреса etcnet"
set_hostname_tz isp
backup_dir /etc/net
eth_iface ens33 dhcp
eth_iface ens37 static 172.16.1.1/28
eth_iface ens38 static 172.16.2.1/28
step "M1 · ISP: ip_forward + NAT"
enable_forwarding
write_nat "172.16.1.0/28, 172.16.2.0/28"
apply_network
finish "ISP (модуль 1)"
