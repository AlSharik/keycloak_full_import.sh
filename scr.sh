#!/bin/bash

# Исходные параметры для экспорта
EXPORT_KEYCLOAK_URL=""
EXPORT_KEYCLOAK_REALM=""
EXPORT_KEYCLOAK_USER=""
EXPORT_KEYCLOAK_SECRET=""
EXPORT_REALM_NAME=""

# Параметры для импорта
IMPORT_KEYCLOAK_URL=""
IMPORT_KEYCLOAK_REALM=""
IMPORT_KEYCLOAK_USER=""
IMPORT_KEYCLOAK_SECRET=""
IMPORT_REALM_NAME=""

# Получение токена доступа
get_access_token() {
  local keycloak_url=$1
  local keycloak_realm=$2
  local keycloak_user=$3
  local keycloak_secret=$4

  curl -X POST "${keycloak_url}/auth/realms/${keycloak_realm}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${keycloak_user}" \
    -d "password=${keycloak_secret}" \
    -d "grant_type=password" \
    -d 'client_id=admin-cli' | jq -r '.access_token'
}

# Экспорт реалма, пользователей, ролей и групп
export_data() {
  local access_token=$1

  # Экспорт реалма
  curl -X GET "${EXPORT_KEYCLOAK_URL}/auth/admin/realms/${EXPORT_REALM_NAME}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${access_token}" \
    > keycloak_${EXPORT_REALM_NAME}_realm.json

  # Экспорт пользователей
  curl -X GET "${EXPORT_KEYCLOAK_URL}/auth/admin/realms/${EXPORT_REALM_NAME}/users" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${access_token}" \
    > keycloak_${EXPORT_REALM_NAME}_users.json

  # Экспорт ролей
  curl -X GET "${EXPORT_KEYCLOAK_URL}/auth/admin/realms/${EXPORT_REALM_NAME}/roles" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${access_token}" \
    > keycloak_${EXPORT_REALM_NAME}_roles.json

  # Экспорт групп
  curl -X GET "${EXPORT_KEYCLOAK_URL}/auth/admin/realms/${EXPORT_REALM_NAME}/groups" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${access_token}" \
    | jq 'walk(if type == "object" then del(.id) else . end)' > keycloak_${EXPORT_REALM_NAME}_groups.json
}

# Установка пароля для пользователя
set_user_password() {
  local access_token=$1
  local realm=$2
  local username=$3
  local password=$4

  # Получение ID пользователя
  local user_id=$(curl -s -X GET "${IMPORT_KEYCLOAK_URL}/auth/admin/realms/${realm}/users?username=${username}" \
    -H "Authorization: Bearer ${access_token}" | jq -r '.[0].id')

  # Установка нового пароля
  curl -s -X PUT "${IMPORT_KEYCLOAK_URL}/auth/admin/realms/${realm}/users/${user_id}/reset-password" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}"
}

# Импорт реалма, пользователей, ролей и групп
import_data() {
  local access_token=$1

  # Импорт реалма
  local realm_file="keycloak_${IMPORT_REALM_NAME}_realm.json"
  [ -f "$realm_file" ] && curl -X POST "${IMPORT_KEYCLOAK_URL}/auth/admin/realms" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${access_token}" \
    -d @$realm_file

  # Импорт пользователей с установкой пароля
  local users_file="keycloak_${IMPORT_REALM_NAME}_users.json"
  if [ -f "$users_file" ]; then
    jq -c '.[]' "$users_file" | while read -r user; do
      local username=$(echo "$user" | jq -r '.username')
      curl -X POST "${IMPORT_KEYCLOAK_URL}/auth/admin/realms/${IMPORT_REALM_NAME}/users" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${access_token}" \
        -d "$user" \
        && set_user_password "$access_token" "$IMPORT_REALM_NAME" "$username" "1"
    done
  fi

  # Импорт ролей
  local roles_file="keycloak_${IMPORT_REALM_NAME}_roles.json"
  if [ -f "$roles_file" ]; then
    jq -c '.[]' "$roles_file" | while read -r role; do
      curl -X POST "${IMPORT_KEYCLOAK_URL}/auth/admin/realms/${IMPORT_REALM_NAME}/roles" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${access_token}" \
        -d "$role"
    done
  fi

  # Импорт групп
  local groups_file="keycloak_${IMPORT_REALM_NAME}_groups.json"
  if [ -f "$groups_file" ]; then
    jq -c '.[]' "$groups_file" | while read -r group; do
      curl -X POST "${IMPORT_KEYCLOAK_URL}/auth/admin/realms/${IMPORT_REALM_NAME}/groups" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${access_token}" \
        -d "$group"
    done
  fi
}

# Основной рабочий процесс скрипта
export_access_token=$(get_access_token $EXPORT_KEYCLOAK_URL $EXPORT_KEYCLOAK_REALM $EXPORT_KEYCLOAK_USER $EXPORT_KEYCLOAK_SECRET)
export_data $export_access_token

import_access_token=$(get_access_token $IMPORT_KEYCLOAK_URL $IMPORT_KEYCLOAK_REALM $IMPORT_KEYCLOAK_USER $IMPORT_KEYCLOAK_SECRET)
import_data $import_access_token

# Удаление всех JSON файлов в текущей директории
rm -f *.json

