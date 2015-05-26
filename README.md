# Database Backup
A simple bash script to manage database backups.

## What does it do?
This script creates a backup of all user created databases. compresses, encrypts and signs them. It keeps a copy locally and uploads a copy to a remote location.

It prunes the past backups on the following schedule:
- Keep all backups created in the 24 hours
- Keep the latest daily backup for 30 days
- Keep the latest weekly backup for 1 year.
- Remove backups older then 1 year.

## Why bash?
It's installed on every *nix OS and It's ideal for systems with limited computing resources.

## Installation
Install mysql client and mysqldump.

Place a copy of the bin/dbackup bash script in your path.

## Usage
Run `dbackup`

The default behavior is to login with the current user without a password. Backup all databases from the local server to the current directory.

Run ` dbackup --help` for a list of options

## TODO
- Add support for S3
- Add support for GnuPG
- Add email notification
- Add logging
- Add support for Postgres
- Add support to manage backups for multiple remote servers

## Changelog
2015-05-25	-	0.0.1	-	Development release posted to github

## Credits
[Ceaser Larry](<https://github.com/ceaser)

+ 2015 Divergent Logic, LLC


