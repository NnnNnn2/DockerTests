#!/bin/bash
# !!! UWAGA, UMIESC TEN PLIK W KONTENERZE ProxySQL W /usr/local/bin !!!
# nastepnie uruchom te komendy
# chmod +x /usr/local/bin/failover_safe.sh
# chown proxysql:proxysql /usr/local/bin/failover_safe.sh

# --- KONFIGURACJA ---
MONITOR_USER="monitor"
MONITOR_PASS="monitor"
PROXY_ADMIN_USER="admin"
PROXY_ADMIN_PASS="admin"
PROXY_IP="127.0.0.1"
PROXY_PORT="6032"

MASTER_IP="192.168.100.6"
SLAVE_IP="192.168.100.7"
LOG_FILE="/var/lib/proxysql/proxysql_failover.log" # Zmiana na katalog ProxySQL dla łatwiejszych uprawnień
LOCK_FILE="/tmp/proxysql_failover.lock"

# --- ZABEZPIECZENIE PRZED WIELOKROTNYM URUCHOMIENIEM ---
if [ -e "$LOCK_FILE" ]; then
    # Sprawdź, czy proces rzeczywiście żyje
    if kill -0 $(cat "$LOCK_FILE") 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# --- LOGIKA ---

# 1. Sprawdź czy Master (VM2) odpowiada
# Używamy --skip-ssl oraz --protocol=tcp dla stabilności
mysqladmin -u"$MONITOR_USER" -p"$MONITOR_PASS" -h"$MASTER_IP" --protocol=tcp --skip-ssl ping > /dev/null 2>&1

if [ $? -ne 0 ]; then
    # MASTER PADŁ - Rozpocznij procedurę ratunkową
    
    # A. Sprawdź czy Slave (VM3) jest nadal w trybie read_only
    # Dodajemy timeout, żeby skrypt nie wisiał w nieskończoność
    IS_RO=$(mysql -u"$MONITOR_USER" -p"$MONITOR_PASS" -h"$SLAVE_IP" --protocol=tcp --skip-ssl --connect-timeout=5 -Nbe "SELECT @@global.read_only" 2>/dev/null)

    if [ "$IS_RO" == "1" ]; then
        echo "$(date): MASTER DOWN ($MASTER_IP). Starting promotion of $SLAVE_IP..." >> "$LOG_FILE"

        # B. Wyłącz read_only na Slave (Promocja)
        mysql -u"$MONITOR_USER" -p"$MONITOR_PASS" -h"$SLAVE_IP" --protocol=tcp --skip-ssl -e "SET GLOBAL read_only=0;" 2>> "$LOG_FILE"
        
        # C. ZABLOKUJ STARY MASTER W PROXYSQL
        # Wysyłamy komendę do interfejsu administracyjnego
        mysql -u"$PROXY_ADMIN_USER" -p"$PROXY_ADMIN_PASS" -h"$PROXY_IP" -P"$PROXY_PORT" --protocol=tcp --skip-ssl -e \
        "UPDATE mysql_servers SET status='OFFLINE_SOFT' WHERE hostname='$MASTER_IP'; LOAD MYSQL SERVERS TO RUNTIME;" 2>> "$LOG_FILE"
        
        if [ $? -eq 0 ]; then
            echo "$(date): SUCCESS - $SLAVE_IP promoted, $MASTER_IP set to OFFLINE_SOFT." >> "$LOG_FILE"
        else
            echo "$(date): ERROR - Failed to update ProxySQL configuration!" >> "$LOG_FILE"
        fi
    fi
fi
