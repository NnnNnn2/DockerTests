-- Dodanie Mastera (VM2) do grupy 10
INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'IP_VM2', 3306);

-- Dodanie Slave'a (VM3) do grupy 20
INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (20, 'IP_VM3', 3306);

-- Ustawienie użytkownika WordPressa
INSERT INTO mysql_users (username, password, default_hostgroup) 
VALUES ('wordpress_user', 'wordpress_password', 10);

-- Konfiguracja przełączania awaryjnego
INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup, check_type)
VALUES (10, 20, 'mysql_slave_status');

-- Zapisanie i aktywowanie zmian
LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL USERS TO RUNTIME;
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL USERS TO DISK;
SAVE MYSQL VARIABLES TO DISK;

exit
