#!/bin/bash

# Установи URL API и ключи
DOMAIN=""
API_URL="https://api.porkbun.com/api/json/v3/domain/checkDomain/$DOMAIN"
SECRET_API_KEY=""
API_KEY=""
CHAT_ID="-"
BOT_TOKEN=""

# Функция для URL кодирования
urlencode() {
    local str="$1"
    echo -n "$str" | jq -sRr @uri
}

# Инициализация счетчика
counter=1

# Основной цикл
while true; do
    # Выполнение запроса через curl
    RESPONSE=$(curl --silent --location "$API_URL" \
        --header 'Content-Type: text/plain' \
        --data '{
            "secretapikey": "'"$SECRET_API_KEY"'",
            "apikey": "'"$API_KEY"'"
        }')

    # Проверка доступности домена
    AVAILABILITY=$(echo "$RESPONSE" | jq -r '.response.avail')

    # Формирование сообщения
    if [[ "$AVAILABILITY" == "no" ]]; then
        MESSAGE="Запрещена регистрация домена $DOMAIN"
    else
        MESSAGE="Домен $DOMAIN доступен для регистрации!"
        # Отправка сообщения в Telegram только если домен доступен
        ENCODED_MESSAGE=$(urlencode "$MESSAGE")
        curl --silent --location "https://api.telegram.org/bot$BOT_TOKEN/sendMessage?chat_id=$CHAT_ID&text=$ENCODED_MESSAGE" > /dev/null 2>&1
    fi

    # Вывод сообщения и номера итерации в одну строку с переносом
    echo "#$counter - $MESSAGE"

    # Увеличение счетчика
    ((counter++))

    # Ожидание 15 секунд
    sleep 15
done
