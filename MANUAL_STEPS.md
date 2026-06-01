# Ручные пункты после запуска скриптов

## Proxmox/PVE

Создать сети:

- ISP WAN: внешний bridge для `ens19` ISP;
- ISP-HQ: bridge для ISP ↔ HQ-RTR, сеть `172.16.70.0/28`;
- ISP-BR: bridge для ISP ↔ BR-RTR, сеть `172.16.80.0/28`;
- BR-NET: bridge для BR-RTR ↔ BR-SRV, сеть `192.168.3.0/28`;
- HQ-TRUNK: VLAN-aware bridge для HQ-RTR ↔ HQ-SRV/HQ-CLI.

VLAN:

- HQ-SRV: VLAN Tag 100;
- HQ-CLI: VLAN Tag 200;
- management: VLAN 999, если используется.

## Проверки стенда 1

```bash
# HQ-SRV
ping 192.168.1.1
ping 192.168.3.10
ping br-srv.au-team.irpo

# BR-SRV
ping 192.168.3.1
ping 192.168.1.10
ping hq-srv.au-team.irpo

# HQ-CLI
ip -4 a
ping 192.168.2.1
ping 192.168.1.10
```

## Проверки стенда 2

```bash
# BR-SRV
samba-tool domain info 127.0.0.1
ansible all -m ping
cd /root/testapp && docker compose ps

# HQ-SRV
df -h
exportfs -v
systemctl status rsyslog fail2ban
cd /root/zabbix && docker compose ps

# HQ-CLI
mount | grep /mnt/nfs
lpstat -p -d
```

## Задание 3.3

Не выполнять. В файлах EcoRouter для стенда 2 нет `crypto-ipsec`, `crypto-map`, IKE profile и привязки IPsec к GRE. Это сделано намеренно.
