# Dok 4 — два стенда со скриптами

Основание: `Dok 4(1).pdf`.

## Стенд 1 — только модуль 1

Папка: `stand1_module1`.

Автоматизировано:

- hostname на ALT Linux и EcoRouter;
- адресация ISP/HQ/BR;
- локальные учетные записи `sshuser` UID 2014 и `net_admin`;
- безопасный SSH на HQ-SRV/BR-SRV;
- GRE, OSPF, динамический NAT, DHCP на EcoRouter;
- NAT на ISP;
- dnsmasq на HQ-SRV;
- timezone Europe/Moscow.

Порядок запуска:

```bash
# ISP
bash stand1_module1/ISP_M1.sh

# HQ-SRV
bash stand1_module1/HQ-SRV_M1.sh

# BR-SRV
bash stand1_module1/BR-SRV_M1.sh

# HQ-CLI
bash stand1_module1/HQ-CLI_M1.sh
```

На EcoRouter команды не являются bash-скриптами. Их нужно вставить в CLI:

```text
stand1_module1/HQ-RTR_M1.ecorouter.txt
stand1_module1/BR-RTR_M1.ecorouter.txt
```

Остается вручную:

- создание bridge/VLAN в Proxmox/PVE;
- VLAN-aware trunk к HQ-RTR и VLAN Tag 100/200 на HQ-SRV/HQ-CLI;
- проверка фактических имен интерфейсов ALT Linux (`ip -br link`);
- сохранение конфигурации EcoRouter;
- проверка DHCP на HQ-CLI и связности HQ ↔ BR.

## Стенд 2 — модули 2 и 3, но без задания 3.3

Папка: `stand2_modules2_3_no_3_3`.

Предпосылка: на втором стенде уже должна быть поднята базовая сеть модуля 1. Если стенд чистый, сначала выполните скрипты из `stand1_module1`.

Задание 3.3 — перенос GRE на защищенный IPSec/IKE-туннель — намеренно не выполняется. GRE/OSPF из модуля 1 остаются рабочими.

Порядок запуска:

```bash
# ISP
bash stand2_modules2_3_no_3_3/ISP_M2_M3_no3_3.sh

# HQ-SRV, перед запуском проверьте диски lsblk
DISK1=/dev/sdb DISK2=/dev/sdc bash stand2_modules2_3_no_3_3/HQ-SRV_M2_M3_no3_3.sh

# BR-SRV
bash stand2_modules2_3_no_3_3/BR-SRV_M2_M3_no3_3.sh

# HQ-CLI
bash stand2_modules2_3_no_3_3/HQ-CLI_M2_M3_no3_3.sh
```

На EcoRouter вставить вручную:

```text
stand2_modules2_3_no_3_3/HQ-RTR_M2_M3_no3_3.ecorouter.txt
stand2_modules2_3_no_3_3/BR-RTR_M2_M3_no3_3.ecorouter.txt
```

## Additional.iso

Модули 2-3 используют `Additional.iso`: `Users.csv`, Docker-образы, web-файлы, dump.sql, playbook, Cyber Backup. Скрипты ищут ISO на `/dev/sr0` и монтируют в `/mount`.

Если ISO подключен как второй CD-ROM, запускайте так:

```bash
ISO_DEV=/dev/sr1 bash stand2_modules2_3_no_3_3/BR-SRV_M2_M3_no3_3.sh
ISO_DEV=/dev/sr1 bash stand2_modules2_3_no_3_3/HQ-SRV_M2_M3_no3_3.sh
```

## Принятые решения по противоречиям в PDF

В документе есть несколько внутренних расхождений. В скриптах выбраны рабочие значения:

- ISP: `ens20 = HQ 172.16.70.1/28`, `ens21 = BR 172.16.80.1/28`. Это соответствует пошаговой настройке ISP; верхняя таблица в PDF указывает интерфейсы наоборот.
- SSH: в тексте встречается 2026, но команда на странице 5 задает `Port 2014`. Скрипты включают оба порта: 2014 и 2026. Основной порт для Ansible — 2014.
- RAID: задание требует RAID0 `/dev/md0` на двух дисках, а ниже в PDF встречается невозможная команда RAID5 на двух дисках. Скрипт делает RAID0 `/dev/md0`.
- Chrony: задание требует stratum 5, в одном месте команды указан stratum 9. Скрипт ставит stratum 5.
- Static NAT: в PDF местами остались старые адреса `172.16.1.2/172.16.2.2`; скрипты используют адреса Dok 4: `172.16.70.2/172.16.80.2`.

## Что остается вручную

Стенд 1:

- PVE/Proxmox network, VLAN-aware bridge, VLAN Tag 100/200/999;
- вставка и сохранение EcoRouter-конфигов;
- проверка DHCP, DNS, GRE/OSPF, NAT.

Стенд 2:

- ввод HQ-CLI в домен через GUI/ЦУС: `au-team.irpo`, Administrator, `123qweR%`, затем reboot;
- `sudo-schema-apply`, `create-sudo-rule`, ADMC: правило `prava_hq`, `%hq`, `/bin/cat`, `/bin/grep`, `/usr/bin/id`, `!authenticate`;
- проверка структуры `Users.csv`, затем импорт: `/root/import_users_from_csv.sh /opt/Users.csv` на BR-SRV;
- копирование сертификатов с HQ-SRV `/root/ca-gost/*.cer/*.key` на ISP `/etc/nginx/ssl`, затем повторный запуск скрипта ISP;
- копирование `ca.cer` на HQ-CLI в `/home/user/ca.cer`, затем повторный запуск скрипта HQ-CLI;
- установка CryptoPro CSP через GUI;
- проверка `/var/www/html/index.php` на HQ-SRV;
- Zabbix GUI: hosts HQ-SRV/BR-SRV, dashboards, пароль admin → `P@ssw0rd`;
- Cyber Backup GUI: организация `irpo`, пользователь `irpoadmin/P@ssw0rd`, storage node HQ-CLI `/backup`, планы `/etc` и MySQL `webdb`;
- сохранение конфигурации EcoRouter.
