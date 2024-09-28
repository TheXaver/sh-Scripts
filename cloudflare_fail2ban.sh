#!/bin/bash

ACTION=$1
IP=$2
API_TOKEN=$3
ZONE_ID=$4

FILE="/etc/fail2ban/scripts/cloudflare_banned_ips.txt"
LOG_FILE="/etc/fail2ban/scripts/cloudflare_banned_ips_log.txt"

if [ "$ACTION" == "ban" ]; then
    REQUEST_DATA=$(cat <<EOF
{
    "mode": "block",
    "configuration": {
        "target": "ip",
        "value": "$IP"
    },
    "notes": "Blocked by Fail2Ban"
}
EOF
)

    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$REQUEST_DATA")

    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')

    if [ "$SUCCESS" == "true" ]; then
        RULE_ID=$(echo "$RESPONSE" | jq -r '.result.id')
        sed -i "/^$IP:/d" "$FILE"
        echo "$IP:$RULE_ID" >> "$FILE"
        # Добавляем IP и время в лог-файл, если его там еще нет
        if ! grep -q "^$IP$" "$LOG_FILE"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $IP" >> "$LOG_FILE"
        fi
    else
        ERROR_CODE=$(echo "$RESPONSE" | jq -r '.errors[0].code')
        if [ "$ERROR_CODE" == "10009" ]; then
            RESPONSE_GET=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules?configuration.value=$IP&configuration.target=ip" \
                -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json")

            SUCCESS_GET=$(echo "$RESPONSE_GET" | jq -r '.success')

            if [ "$SUCCESS_GET" == "true" ]; then
                RULE_ID=$(echo "$RESPONSE_GET" | jq -r '.result[0].id')
                CURRENT_MODE=$(echo "$RESPONSE_GET" | jq -r '.result[0].mode')

                if [ "$CURRENT_MODE" != "block" ]; then
                    UPDATE_DATA=$(cat <<EOF
{
    "mode": "block",
    "notes": "Updated by Fail2Ban"
}
EOF
)

                    RESPONSE_UPDATE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules/$RULE_ID" \
                        -H "Authorization: Bearer $API_TOKEN" \
                        -H "Content-Type: application/json" \
                        --data "$UPDATE_DATA")

                    SUCCESS_UPDATE=$(echo "$RESPONSE_UPDATE" | jq -r '.success')

                    if [ "$SUCCESS_UPDATE" == "true" ]; then
                        sed -i "/^$IP:/d" "$FILE"
                        echo "$IP:$RULE_ID" >> "$FILE"
                        # Добавляем IP и время в лог-файл, если его там еще нет
                        if ! grep -q "^$IP$" "$LOG_FILE"; then
                            echo "$(date '+%Y-%m-%d %H:%M:%S') - $IP" >> "$LOG_FILE"
                        fi
                    else
                        exit 1
                    fi
                else
                    sed -i "/^$IP:/d" "$FILE"
                    echo "$IP:$RULE_ID" >> "$FILE"
                    # Добавляем IP и время в лог-файл, если его там еще нет
                    if ! grep -q "^$IP$" "$LOG_FILE"; then
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - $IP" >> "$LOG_FILE"
                    fi
                fi
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi

elif [ "$ACTION" == "unban" ]; then
    RULE_ID=$(grep "^$IP:" "$FILE" | cut -d':' -f2 | head -n1)

    if [ -z "$RULE_ID" ]; then
        RESPONSE_GET=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules?configuration.value=$IP&configuration.target=ip" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json")

        SUCCESS_GET=$(echo "$RESPONSE_GET" | jq -r '.success')
        if [ "$SUCCESS_GET" == "true" ] && [ "$(echo "$RESPONSE_GET" | jq -r '.result | length')" -gt 0 ]; then
            RULE_ID=$(echo "$RESPONSE_GET" | jq -r '.result[0].id')
        else
            sed -i "/^$IP:/d" "$FILE"
            exit 0
        fi
    fi

    RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/access_rules/rules/$RULE_ID" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json")

    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')

    if [ "$SUCCESS" == "true" ]; then
        sed -i "/^$IP:/d" "$FILE"
        # Не удаляем IP из лог-файла
    else
        ERROR_CODE=$(echo "$RESPONSE" | jq -r '.errors[0].code')
        if [ "$ERROR_CODE" == "1003" ]; then
            sed -i "/^$IP:/d" "$FILE"
            exit 0
        else
            exit 1
        fi
    fi
fi
