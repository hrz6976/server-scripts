#!/bin/bash
# based on https://gist.github.com/Tras2/cba88201b17d765ec065ccbedfb16d9a

set -e

# import settings from .env
CWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
if [ -f "$CWD/.env" ]; then
    source "$CWD/.env"
fi

# get the basic data
ipv4=$(ip r g 1.0.0.0 | grep -oP 'src \K\S+')
ipv6=$(ip r g 2606:4700:4700::1111 | grep -oP 'src \K\S+')
date=$(date '+%Y-%m-%d %H:%M:%S')

user_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
               -H "Authorization: Bearer $CF_API_TOKEN" \
               -H "Content-Type:application/json" \
          | jq -r '{"result"}[] | .id'
         )

# write down IPv4 and/or IPv6
if [ $ipv4 ]; then echo -e "\033[0;32m [+] Your public IPv4 address: $ipv4"; else echo -e "\033[0;33m [!] Unable to get any public IPv4 address."; fi
if [ $ipv6 ]; then echo -e "\033[0;32m [+] Your public IPv6 address: $ipv6"; else echo -e "\033[0;33m [!] Unable to get any public IPv6 address."; fi

# check if the user API is valid and the CF_EMAIL is correct
if [ $user_id ]
then
    zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE_NAME&status=active" \
                   -H "Content-Type: application/json" \
                   -H "X-Auth-CF_EMAIL: $CF_EMAIL" \
                   -H "Authorization: Bearer $CF_API_TOKEN" \
              | jq -r '{"result"}[] | .[0] | .id'
             )
    # check if the zone ID is avilable
    if [ $zone_id ]
    then
        # check if there is any IP version 4
        if [ $ipv4 ]
        then
            CF_DNS_RECORD_a_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$CF_DNS_RECORD"  \
                                   -H "Content-Type: application/json" \
                                   -H "X-Auth-CF_EMAIL: $CF_EMAIL" \
                                   -H "Authorization: Bearer $CF_API_TOKEN"
                             )
            # if the IPv4 exist
            CF_DNS_RECORD_a_ip=$(echo $CF_DNS_RECORD_a_id |  jq -r '{"result"}[] | .[0] | .content')
            if [ $CF_DNS_RECORD_a_ip != $ipv4 ]
            then
                # change the A record
                curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$(echo $CF_DNS_RECORD_a_id | jq -r '{"result"}[] | .[0] | .id')" \
                     -H "Content-Type: application/json" \
                     -H "X-Auth-CF_EMAIL: $CF_EMAIL" \
                     -H "Authorization: Bearer $CF_API_TOKEN" \
                     --data "{\"type\":\"A\",\"name\":\"$CF_DNS_RECORD\",\"content\":\"$ipv4\",\"ttl\":1,\"proxied\":false}" \
                | jq -r '.errors'
                # write the result
                echo -e "\033[0;32m [+] $date The IPv4 is successfully set on Cloudflare as the A Record with the value of:    $CF_DNS_RECORD_a_ip"
            else
                echo -e "\033[0;37m [~] $date The current IPv4 and  the existing on on Cloudflare are the same; there is no need to apply it."
            fi
        fi

        # check if there is any IP version 6
        if [ $ipv6 ]
        then
            CF_DNS_RECORD_aaaa_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=AAAA&name=$CF_DNS_RECORD"  \
                                      -H "Content-Type: application/json" \
                                      -H "X-Auth-CF_EMAIL: $CF_EMAIL" \
                                      -H "Authorization: Bearer $CF_API_TOKEN"
                                )
            # if the IPv6 exist
            CF_DNS_RECORD_aaaa_ip=$(echo $CF_DNS_RECORD_aaaa_id | jq -r '{"result"}[] | .[0] | .content')
            if [ $CF_DNS_RECORD_aaaa_ip != $ipv6 ]
            then
                # change the AAAA record
                curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$(echo $CF_DNS_RECORD_aaaa_id | jq -r '{"result"}[] | .[0] | .id')" \
                     -H "Content-Type: application/json" \
                     -H "X-Auth-CF_EMAIL: $CF_EMAIL" \
                     -H "Authorization: Bearer $CF_API_TOKEN" \
                     --data "{\"type\":\"AAAA\",\"name\":\"$CF_DNS_RECORD\",\"content\":\"$ipv6\",\"ttl\":1,\"proxied\":false}" \
                | jq -r '.errors'
                # write the result
                echo -e "\033[0;32m [+] $date The IPv6 is successfully set on Cloudflare as the AAAA Record with the value of: $CF_DNS_RECORD_aaaa_ip"
            else
                echo -e "\033[0;37m [~] $date The current IPv6 address and the existing on on Cloudflare are the same; there is no need to apply it."
            fi
        fi
    else
        echo -e "\033[0;31m [-] There is a problem with getting the Zone ID (subdomain) or the CF_EMAIL address (username). Check them and try again."
    fi
else
    echo -e "\033[0;31m [-] There is a problem with either the API token. Check it and try again."
fi