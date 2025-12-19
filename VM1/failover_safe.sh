#!/bin/bash
# !!! UWAGA, UMIEŚĆ TEN PLIK W KONTENERZE ProxySQL W /usr/local/bin !!!
# --- KONFIGURACJA ---
MONITOR_USER="monitor"
MONITOR_PASS="monitor"
PROXY_ADMIN_USER="admin"
PROXY_ADMIN_PASS="admin"
PROXY_IP="127.0.0.1"
PROXY_PORT="6032"

MASTER_IP="192.168.100.6"
SLAVE_IP="192.168.100.7"

# --- LOGIKA ---

# 1. Sprawdź czy Master (VM2) odpowiada
mysqladmin -u$MONITOR_USER -p$MONITOR_PASS -h$MASTER_IP ping > /dev/null 2>&1

if [ $? -ne 0 ]; then
    # MASTER PADŁ - Rozpocznij procedurę ratunkową
    
    # A. Sprawdź czy Slave (VM3) jest nadal w trybie read_only
    IS_RO=$(mysql -u$MONITOR_USER -p$MONITOR_PASS -h$SLAVE_IP -Nbe "SELECT @@global.read_only")

    if [ "$IS_RO" == "1" ]; then
        # B. Wyłącz read_only na Slave (Promocja)
        mysql -u$MONITOR_USER -p$MONITOR_PASS -h$SLAVE_IP -e "SET GLOBAL read_only=0;"
        
        # C. ZABLOKUJ STARY MASTER W PROXYSQL (Ochrona przed Split-Brain)
        # Ustawiamy status OFFLINE_SOFT, żeby ProxySQL go ignorował nawet jak wstanie
        mysql -u$PROXY_ADMIN_USER -p$PROXY_ADMIN_PASS -h$PROXY_IP -P$PROXY_PORT -e \
        "UPDATE mysql_servers SET status='OFFLINE_SOFT' WHERE hostname='$MASTER_IP'; LOAD MYSQL SERVERS TO RUNTIME;"
        
        echo "$(date): Master $MASTER_IP down. $SLAVE_IP promoted and $MASTER_IP set to OFFLINE_SOFT." >> /var/log/proxysql_failover.log
    fi
fi
