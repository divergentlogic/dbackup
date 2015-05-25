#!/bin/bash

NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"

ROOTDIR=$(pwd -P)
source "${ROOTDIR}/bin/dbackup"

################################################################################
# Test Framework
################################################################################
STATUS=""
STATUS_MSG=""
pending_status()
{
  STATUS="${YELLOW}Pending"
  STATUS_MSG="${NC}"
}

pass_status()
{
  STATUS="${GREEN}Passed"
  STATUS_MSG="${NC}"
}

fail_status()
{
  STATUS="${RED}Failed:"
  STATUS_MSG="$1${NC}"
}

print_status()
{
  printf "${STATUS} ${STATUS_MSG}"
}

run()
{
  pending_status
  desc $1
  before
  eval $1
  after
  print_status
  printf "\n\n"
}

desc()
{
  printf "${CYAN}- ${1}:${NC}\n"
}

################################################################################
# Assertions
################################################################################
assert_empty()
{
  [[ -z $1 ]] && pass_status || fail_status "Expected a empty value. Got '$1'"
}

assert_not_empty()
{
  [[ ! -z $1 ]] && pass_status || fail_status "Expected a value"
}

assert_equal()
{
  [[ $1 == $2 ]] && pass_status || fail_status "'$1' != '$2'"
}

################################################################################
# Test Helpers
################################################################################
mysql_command()
{
  $(`which mysql` -e "$1")
}

create_backup_dir()
{
  if [ ! -z "${BACKUP_DIR}" ] || [ -d "${BACKUP_DIR}" ]
  then
    return
  fi

  BACKUP_DIR=$(mktemp -t dbackup_test-XXX -d)
}

################################################################################
# Tests
################################################################################
before_once()
{
  mysql_command "DROP DATABASE IF EXiSTS backup_test;"
  mysql_command "CREATE DATABASE backup_test;"
}

before()
{
  echo "" > /dev/null
}

after_once()
{
  mysql_command "DROP DATABASE IF EXiSTS backup_test;"
}

after()
{
  [ -d ${BACKUP_DIR} ] && $(/bin/rm -rf "${BACKUP_DIR}")

  unset MYSQL_DATABASES
  unset TIMESTAMP
  unset MYSQL_LOGIN_PATH
  unset MYSQL_HOST
  unset MYSQL_PASSWORD
  unset MYSQL_PORT
  unset MYSQL_USER
  unset BACKUP_DIR
}

should_display_usage_dialog()
{
  local ACTUAL="$((usage) 2>&1)"
  assert_not_empty $ACTUAL
}

should_have_mysql_database_list()
{
  mysql_databases
  assert_not_empty ${MYSQL_DATABASES}
}

should_generate_timestamp()
{
  generate_timestamp
  assert_not_empty $TIMESTAMP
}

should_create_mysql_backup_files()
{
  # Setup
  MYSQL_DATABASES="backup_test"
  BACKUP_DIR=$(mktemp -t dbackup_test-XXX -d)

  # Test
  backup_mysql
  assert_equal $(basename ${BACKUP_DIR}/*.sql.gz) "-backup_test.sql.gz"
}

should_have_timestamp_on_backup_files_if_variable_is_set()
{
  # Setup
  MYSQL_DATABASES="backup_test"
  BACKUP_DIR=$(mktemp -t dbackup_test-XXX -d)
  TIMESTAMP="time"

  # Test
  backup_mysql
  assert_equal $(basename ${BACKUP_DIR}/*.sql.gz) "time-backup_test.sql.gz"
}

should_keep_1_backup_a_day_for_the_last_30_days()
{
  create_backup_dir

  # Create 31 days of hourly backups
  for i in {0..748}
  do
    if [[ ${PLATFORM} == 'linux' ]]; then
      local TIMESTAMP=$(date --date="${i} hours ago" +"%C%y%m%d%H%M")
    else
      local TIMESTAMP=$(date -j -v-"${i}H" +"%C%y%m%d%H%M")
    fi
    touch -t "${TIMESTAMP}" "${BACKUP_DIR}/${TIMESTAMP}-backup_test.sql.gz"
  done

  purge_30_days

  # Count the number of files last left. Not including the current day or any files after 30 days.
  if [[ ${PLATFORM} == 'linux' ]]; then
    local FROM=$(date --date="30 days ago" +"%C%y-%m-%d 00:00")
    local TO=$(date --date="23 hours ago" +"%C%y-%m-%d %H:%M")
  else
    local FROM=$(date -j -v-30d +"%Y-%m-%d %H:%M")
    local TO=$(date -j -v-23H +"%Y-%m-%d %H:%M")
  fi
  local ACTUAL=$(/usr/bin/find "${BACKUP_DIR}" -type f -newermt "${FROM}" ! -newermt "${TO}" | wc -l)

  assert_equal ${ACTUAL} 30
}

should_keep_all_backups_created_in_the_last_24_hours()
{
  create_backup_dir

  # Create 2 days of hourly backups
  for i in {0..48}
  do
    if [[ ${PLATFORM} == 'linux' ]]; then
      local TIMESTAMP=$(date --date="${i} hours ago" +"%C%y%m%d%H%M")
    else
      local TIMESTAMP=$(date -j -v-${i}H +"%C%y%m%d%H%M")
    fi
    touch -t "${TIMESTAMP}" "${BACKUP_DIR}/${TIMESTAMP}-backup_test.sql.gz"
  done

  purge_30_days

  # Count the number of files last left. Not including the current day or any files after 30 days.
  if [[ ${PLATFORM} == 'linux' ]]; then
    local FROM=$(date --date="24 hours ago" +"%C%y-%m-%d %H:%M")
  else
    local FROM=$(date -j -v-24H +"%Y-%m-%d %H:%M")
  fi
  local ACTUAL=$(/usr/bin/find "${BACKUP_DIR}" -type f -newermt "${FROM}" | wc -l)

  assert_equal ${ACTUAL} 24
}

should_keep_1_backup_a_week_after_30_days()
{
  create_backup_dir

  # Create 356 days of backups
  for i in {0..365}
  do
    if [[ ${PLATFORM} == 'linux' ]]; then
      local TIMESTAMP=$(date --date="${i} days ago" +"%C%y%m%d%H%M")
    else
      local TIMESTAMP=$(date -j -v-"${i}d" +"%C%y%m%d%H%M")
    fi
    touch -t "${TIMESTAMP}" "${BACKUP_DIR}/${TIMESTAMP}-backup_test.sql.gz"
  done

  purge_weekly

  # Count the number of files last left. Not including the current day or any files after 30 days.
  if [[ ${PLATFORM} == 'linux' ]]; then
    local TO=$(date --date="29 days ago" +"%C%y-%m-%d 00:00")
  else
    local TO=$(date -j -v-29d +"%Y-%m-%d 00:00")
  fi
  local ACTUAL=$(/usr/bin/find "${BACKUP_DIR}" -type f ! -newermt "${TO}" | wc -l)

  # (365 days - 30 days) / 7 days = 47.85 backups
  assert_equal ${ACTUAL} 47
}

should_delete_any_backup_older_then_a_year()
{
  create_backup_dir

  # Create 356 days of backups
  for i in {1..2}
  do
    if [[ ${PLATFORM} == 'linux' ]]; then
      local TIMESTAMP=$(date --date="${i} years ago" +"%C%y%m%d%H%M")
    else
      local TIMESTAMP=$(date -j -v-"${i}y" +"%C%y%m%d%H%M")
    fi
    touch -t "${TIMESTAMP}" "${BACKUP_DIR}/${TIMESTAMP}-backup_test.sql.gz"
  done
  set +x

  purge_weekly

  local ACTUAL=$(/usr/bin/find "${BACKUP_DIR}" -type f | wc -l)
  assert_equal ${ACTUAL} 0
}

before_once
run should_display_usage_dialog
run should_have_mysql_database_list
run should_generate_timestamp
run should_create_mysql_backup_files
run should_have_timestamp_on_backup_files_if_variable_is_set
run should_keep_1_backup_a_day_for_the_last_30_days
run should_keep_all_backups_created_in_the_last_24_hours
run should_keep_1_backup_a_week_after_30_days
run should_delete_any_backup_older_then_a_year
after_once
