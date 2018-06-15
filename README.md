# mysql_backup

## Description:
MySQL Databases backup script; this is intended to be:
- used on SLAVE servers
- used together with the pre- and post-backup scripts
- run by a scheduler (cron, Jenkins etc.)

## Features:
- preliminary checks to make sure it can/should start the backup dump
- calls the pre-backup script to obtain a list of tables that should be excluded from backup
- stops the replication thread before dump
- dumps specified or all databases in a single file or each table/file (depending on the database)
- calculates SHA1SUM hashes for each .sql file
- compresses each .sql file with bzip2 or gzip - configurable
- encrypts the compressed files with GPG (a GPG private key must be accessible)
- compression and encryption are executed on-the-fly (in memory); no unencrypted data is written to disk!

## Notes:
- databases and tables names MUST NOT contain spaces
- encryption can NOT be turned off
