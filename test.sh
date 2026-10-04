#!/usr/bin/bash

verification_ipv4_octet='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
verification_ipv4="^($verification_ipv4_octet\.){3}$verification_ipv4_octet$"

vps_addr="$1" 
vps_port_ssh="$2"
read -rp "Please enter local port: " local_port
read -rp "Please enter remote port: " remote_port

#############################
#Обработка значений
if [[ ! "$vps_port_ssh" =~ ^[0-9]+$ ]] || (( vps_port_ssh < 1  || vps_port_ssh > 65535)) || [[ ! "$vps_addr" =~ $verification_ipv4 ]]; then 
        printf "Invalid ipv4 address or port value"
        exit 1
fi

#Взаимодействие с пользаком
if [ -z "$vps_addr" ] || [ -z "$vps_port_ssh" ]; then
        printf "When launching the script, you need to enter the VPS address and port. Try --help.
example: ./tunnel.sh 192.168.200.1 22."
        exit 1
else
        printf "User input:\n\tPort: %s\n\tAddress: %s\n\tLocal port: %s\n\tRemote port: %s" "$vps_port_ssh" "$vps_addr" "$local_port" "$remote_port"    
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

if (( EUID != 0 )); then
        echo -e "The script requires root access to run.\nTry sudo ./tunnel.sh"
        exit 1
fi
############################

read -rp "Enter the username for connecting to the VPS: " vps_user
echo "Save fingerprint!!!!"

install -d -m 700 /etc/reverse-tunnel
ssh -p $vps_port_ssh \
        -o UserKnownHostsFile=/etc/reverse-tunnel/known_hosts \
        -o StrictHostKeyChecking=ask \
        -o PubkeyAuthentication=no \
        -o PreferredAuthentications=password \
        "$vps_user@$vps_addr" true || exit 1
 

IFS= read -r -s -p 'Password SSH for vps: ' vps_password
printf '\n'

if [[ -z "$vps_password" ]]; then
    printf 'The password is empty.\n' >&2
    exit 1
fi

(
    umask 077
    printf '%s\n' "$vps_password" > /etc/reverse-tunnel/password
)
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