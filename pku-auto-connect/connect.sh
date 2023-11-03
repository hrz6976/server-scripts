#!/bin/bash

# import settings from .env
CWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
source $CWD/.env

### CONFIG ###
ALWAYS_ONLINE_SITES='http://www.baidu.com http://www.sina.com.cn'
ALWAYS_ONLINE_SITES_V6='http://byr.pt'
CONNECT_PATH='/home/user/connect'
CONNECT_URL="https://its4.pku.edu.cn/cas/ITSClient"

# New API Interface
connect() {
  CONNECT_ARGS="cmd=open&username=${CONNECT_USER}&password=${CONNECT_PASSWORD}&iprange=free"
  curl -Gs -X POST --connect-timeout 5 -d $CONNECT_ARGS  "$CONNECT_URL"
  echo ""
}

send_sc_message() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Missing message or title: message=$1 title=$2"
        return 1
    fi
    curl -Gs "https://sc.ftqq.com/$SCKEY.send" \
        -X POST \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "$(printf 'title=%s' "$1")" \
        --data-urlencode "$(printf 'desp=%s' "$2")"
    echo ""
}

# if --help is specified, print help message and exit
if [ "$1" == "--help" ]; then
    echo "Usage: $0 [--force]"
    echo "  --force: force reconnect even if we are online"
    exit 0
fi

# if --force is specified, set FORCE_CONNECT to 1
if [ "$1" == "--force" ]; then
    FORCE_CONNECT=1
fi

# main routine
SC_TITLE=""
SC_BODY=""

# test whether we are online
for site in $ALWAYS_ONLINE_SITES; do
    echo "Checking link to $site"
    # if redirected to login page, then we are not online
    curl --connect-timeout 5 -s -o /dev/null -I -w "%{http_code}" "$site" | grep -q 302
    if [ $? -eq 0 ] || [ "$FORCE_CONNECT" == "1" ]; then
        # time
        echo $(date +"%Y-%m-%d %H:%M:%S") " Link lost, try reconnecting..."
        connect
        if [ $? -ne 0 ]; then
            # time
            echo "Error: reconnect failed"
            exit 1
        else
            # get_ip
            # printf '%-12s %s\n'  gateway $gateway iface $iface ip $ip
            ip=$(ip route get 1 | grep -oP 'src \K\S+')
            gateway=$(ip route get 1 | grep -oP 'via \K\S+')
            iface=$(ip route get 1 | grep -oP 'dev \K\S+')
            SC_TITLE="Reconnected: $ip"
            SC_BODY="[IPv4] Gateway: $gateway, Interface: $iface, IP: $ip"
            break
        fi
    elif [ -z "$SC_TITLE" ]; then
        echo $(date +"%Y-%m-%d %H:%M:%S") " Link OK"
        break
    fi
done

# check IPv6
for site in $ALWAYS_ONLINE_SITES_V6; do
    echo "Checking link to $site"
    # if redirected to login page, then we are not online
    curl --connect-timeout 5 -s -o /dev/null -I -w "%{http_code}" "$site" | grep -q 302
    if [ $? -eq 0 ] || [ "$FORCE_CONNECT" == "1" ]; then
        # get_ip
        # printf '%-12s %s\n'  gateway $gateway iface $iface ip $ip
        ip=$(ip route get 2606:4700:4700::1111 | grep -oP 'src \K\S+')
        gateway=$(ip route get 2606:4700:4700::1111 | grep -oP 'via \K\S+')
        iface=$(ip route get 2606:4700:4700::1111 | grep -oP 'dev \K\S+')
        SC_BODY="${SC_BODY} [IPv6] Gateway: $gateway, Interface: $iface, IP: $ip"
        break
    else
        # do a curl -v
        SC_BODY="${SC_BODY} [IPv6] $(curl -v --connect-timeout 5 $site)"
        break
    fi
done

if [[ ! -z "$SC_TITLE" ]]; then
    send_sc_message "$SC_TITLE" "$SC_BODY"
    echo $(date +"%Y-%m-%d %H:%M:%S") " Sent $SC_TITLE to ServerChan"
fi