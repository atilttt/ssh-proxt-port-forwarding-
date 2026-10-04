#!/usr/bin/bash

verification_ipv4_octet='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
verification_ipv4="^($verification_ipv4_octet\.){3}$verification_ipv4_octet$"

vps_addr="$1" 
vps_port_ssh="$2"
read -rp "Please enter local port: " local_port
read -rp "Please enter remote port: " remote_port

#############################
if (( $EUID != 0 )); then
        echo "Run as root."
        exit 1
fi

if [ -z "$vps_addr" ] || [ -z "$vps_port_ssh" ]; then
        printf "When launching the script, you need to enter the VPS address and port. Try --help.
example: ./tunnel.sh 192.168.200.1 22."
        exit 1
else
        if [[ ! "$vps_addr" =~ "$verification_ipv4" ]]; then
                printf "Invalid IPv4 address: %s\n" "$vps_addr" 
                exit 1
        fi

        for port in "$vps_port_ssh" "$local_port" "$remote_port"; do
                if [[ ! "$port" =~ "^[0-9]{1,5}$" ]]; then
                        printf "Invalid port: %s\n" "$port"
                        exit 1
                fi

                if (( $port < 1 || $port > 65535)); then
                        printf "Port must be between 1 and 65535: %s\n" "$port"
                        exit 1
                fi
        done
        
        printf "User input:\n\tPort: %s\n\tAddress: %s\n\tLocal port: %s\n\tRemote port: %s\n" "$vps_port_ssh" "$vps_addr" "$local_port" "$remote_port"
        read -p "That’s correct? (y or n (default y)):  " 
        if [[ -n "$REPLY" && "$REPLY" != "y" ]]; then
                printf 'Please try again\n'
                exit 1
        fi
fi

if ! ping -c 5 $vps_addr > /dev/null 2>&1; then
        echo "The host is not available."
        exit 1
fi
#############################

read -rp "Enter the username for connecting to the VPS: " vps_user
echo "Save fingerprint!!!!"

install -d -m 700 /etc/reverse-tunnel || exit 1 
ssh -p $vps_port_ssh \
        -o UserKnownHostsFile=/etc/reverse-tunnel/known_hosts \
        -o StrictHostKeyChecking=ask \
        -o PubkeyAuthentication=no \
        -o PreferredAuthentications=password \
        "$vps_user@$vps_addr" true || exit 1
 

IFS= read -r -s -p 'Password SSH for vps: ' vps_password
printf '\n\n'

if [[ -z "$vps_password" ]]; then
    printf 'The password is empty.\n' >&2
    exit 1
fi

(
    umask 077
    printf '%s\n' "$vps_password" > /etc/reverse-tunnel/password
) || exit 1
unset vps_password
chmod 600 /etc/reverse-tunnel/password




cat > /etc/systemd/system/reverse-tunnel.service <<EOF
[Unit]
Description=Reverse SSH tunnel to VPS
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=/usr/bin/sshpass -f /etc/reverse-tunnel/password /usr/bin/ssh -NT \
    -p ${vps_port_ssh} \
    -o UserKnownHostsFile=/etc/reverse-tunnel/known_hosts \
    -o StrictHostKeyChecking=yes \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password \
    -o NumberOfPasswordPrompts=1 \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -R 127.0.0.1:${remote_port}:127.0.0.1:${local_port} \
    ${vps_user}@${vps_addr}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable reverse-tunnel.service
systemctl restart reverse-tunnel.service

printf 'Logs: journalctl -u reverse-tunnel -f\n'