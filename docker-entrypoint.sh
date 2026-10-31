#!/bin/bash
#VERSION 0.2.3 by @d3vilh@github.com aka Mr. Philipp
set -e

#Variables
EASY_RSA=/usr/share/easy-rsa
OPENVPN_DIR=/etc/openvpn
echo "EasyRSA path: $EASY_RSA OVPN path: $OPENVPN_DIR"

if [[ ! -f $OPENVPN_DIR/pki/ca.crt ]]; then
    export EASYRSA_BATCH=1 # see https://superuser.com/questions/1331293/easy-rsa-v3-execute-build-ca-and-gen-req-silently
    cd $EASY_RSA

    # Building the CA
    echo 'Setting up public key infrastructure...'
    $EASY_RSA/easyrsa init-pki

    # Copy easy-rsa variables (strip CRLF if file was edited on Windows)
    sed 's/\r$//' $OPENVPN_DIR/config/easy-rsa.vars > $EASY_RSA/pki/vars

    # Listing env parameters:
    echo "Following EASYRSA variables will be used:"
    cat $EASY_RSA/pki/vars | awk '{$1=""; print $0}';

    echo 'Generating certificate authority...'
    $EASY_RSA/easyrsa build-ca nopass

    # Creating the Server Certificate, Key, and Encryption Files
    echo 'Creating the Server Certificate...'
    $EASY_RSA/easyrsa gen-req server nopass

    echo 'Sign request...'
    $EASY_RSA/easyrsa sign-req server server

    echo 'Generate Diffie-Hellman key...'
    $EASY_RSA/easyrsa gen-dh

    echo 'Generate HMAC signature...'
    openvpn --genkey tls-auth $EASY_RSA/pki/ta.key

    echo 'Create certificate revocation list (CRL)...'
    $EASY_RSA/easyrsa gen-crl
    chmod +r $EASY_RSA/pki/crl.pem

    # Copy to mounted volume
    cp -r $EASY_RSA/pki/. $OPENVPN_DIR/pki
else

    echo 'PKI already set up.'
fi

# Listing env parameters:
echo "Following EASYRSA variables were set during CA init:"
cat $OPENVPN_DIR/pki/vars | awk '{$1=""; print $0}';

# Configure network
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

echo 'Configuring networking rules...'
if ! grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf; 
  echo 'IP forwarding configuration now applied:'
else
  echo 'IP forwarding configuration already applied:'
fi
sysctl -p /etc/sysctl.conf

echo 'Configuring iptables...'
echo 'NAT for OpenVPN clients'
iptables -t nat -A POSTROUTING -s $TRUST_SUB -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s $GUEST_SUB -o eth0 -j MASQUERADE

echo 'Blocking ICMP for external clients'
iptables -A FORWARD -p icmp -m icmp --icmp-type echo-request -s $GUEST_SUB -j DROP
iptables -A FORWARD -p icmp -m icmp --icmp-type echo-reply -s $GUEST_SUB -j DROP

echo 'Blocking internal home subnet to access from external openvpn clients (Internet still available)'
iptables -A FORWARD -s $GUEST_SUB -d $HOME_SUB -j DROP

if [[ ! -s fw-rules.sh ]]; then
    echo "No additional firewall rules to apply."
else
    echo "Applying firewall rules"
    ./fw-rules.sh
    echo 'Additional firewall rules applied.'
fi

echo 'IPT MASQ Chains:'
iptables -t nat -L | grep MASQ
echo 'IPT FWD Chains:'
iptables -v -x -n -L | grep DROP 

# Management socket: its mode is 0777, so only this directory restricts access.
# The group is shared with the openvpn-ui web process, which is not root.
MI_DIR=$OPENVPN_DIR/run
mkdir -p "$MI_DIR"
chown 0:"${OPENVPN_MI_GID:-61194}" "$MI_DIR" # the host directory can belong to any user
chmod 750 "$MI_DIR"
rm -f "$MI_DIR/mi.sock" # a stale socket would pass the healthcheck without a listener
# Move existing configs off the old TCP port, once the directory is shared with the UI
MI_LEGACY='^management[[:space:]]+[^[:space:]]+[[:space:]]+2080([[:space:]].*)?$'
if grep -q " $MI_DIR " /proc/mounts && grep -qE "$MI_LEGACY" "$OPENVPN_DIR/server.conf"; then
    MI_TMP=$(mktemp)
    sed -E "s|$MI_LEGACY|management $MI_DIR/mi.sock unix|" "$OPENVPN_DIR/server.conf" > "$MI_TMP"
    cat "$MI_TMP" > "$OPENVPN_DIR/server.conf" # in place, server.conf can be a single-file mount
    rm -f "$MI_TMP"
    echo 'Management interface moved to Unix socket.'
fi
grep -qE "^[[:space:]]*management[[:space:]]+$MI_DIR/mi.sock[[:space:]]+unix" "$OPENVPN_DIR/server.conf" ||
    echo "WARNING: server.conf does not use $MI_DIR/mi.sock. The healthcheck and openvpn-ui need this socket."

# OpenVPN keeps the mode of existing files and would create these as root-only
mkdir -p /var/log/openvpn
for MI_LOG in openvpn.log openvpn-status.log; do
    touch "/var/log/openvpn/$MI_LOG"
    chgrp "${OPENVPN_MI_GID:-61194}" "/var/log/openvpn/$MI_LOG"
    chmod 640 "/var/log/openvpn/$MI_LOG"
done

echo 'Start openvpn process...'
exec /usr/sbin/openvpn --cd $OPENVPN_DIR --script-security 2 --config $OPENVPN_DIR/server.conf