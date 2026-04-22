# ozon08/openvpn-server

Fast Docker container with OpenVPN Server living inside.

> **Fork notice:** This repository is a fork of [d3vilh/openvpn-server](https://github.com/d3vilh/openvpn-server) by Mr. Philipp.
> It includes security hardening, updated dependencies, and improved Docker configuration.
> All original credits go to the upstream author. See [CHANGELOG.md](CHANGELOG.md) for a full list of changes made in this fork.

[![latest version](https://img.shields.io/github/v/release/ozon08/openvpn-server?color=%2344cc11&label=LATEST%20RELEASE&style=flat-square&logo=Github)](https://github.com/ozon08/openvpn-server/releases/latest)  [![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/ozon08/openvpn-server/latest?style=flat-square&logo=docker&logoColor=white&label=DOCKER%20IMAGE&color=2344cc11)](https://hub.docker.com/r/ozon08/openvpn-server) ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/ozon08/openvpn-server/latest?logo=Docker&color=2344cc11&label=IMAGE%20SIZE&style=flat-square&logoColor=white)

[![latest version](https://img.shields.io/github/v/release/ozon08/openvpn-ui?color=%2344cc11&label=OpenVPN%20UI&style=flat-square&logo=Github)](https://github.com/ozon08/openvpn-ui) [![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/ozon08/openvpn-ui/latest?logo=docker&label=OpenVPN%20UI%20IMAGE&color=2344cc11&style=flat-square&logoColor=white)](https://hub.docker.com/r/ozon08/openvpn-ui)

## Important changes

### Release `v0.6.2`

#### New

* Bundled `bin/client-disconnect.sh` hook in the image for `openvpn-ui` v0.9.7+ session monitoring. Posts final byte counters and duration to `/api/v1/monitor/disconnect` via `X-Monitor-Token`. To enable, uncomment the `client-disconnect` line in `server.conf` and set `OPENVPN_UI_URL` / `OPENVPN_UI_HOOK_TOKEN` in the openvpn container environment.

#### Fixes

* EasyRSA failure on first start (`-noencys 3650` error) — `easy-rsa.vars` is volume-mounted, so CRLF is now stripped in `docker-entrypoint.sh` at copy time
* Healthcheck was reporting `unhealthy` despite a running container — `CMD-SHELL` uses Alpine's `ash`, which does not support `/dev/tcp/`. Switched to explicit `bash -c`
* `start_period` raised to `900s` to cover initial 4096-bit DH parameter generation on slow hardware
* Removed deprecated `version` key from `docker-compose-no-ui.yml`

### Release `v0.6.1`

* Fixed CRLF line endings in shell scripts causing `exec /opt/app/docker-entrypoint.sh: no such file or directory` on Linux
* Added `.gitattributes` to enforce LF line endings for all scripts and config files

### Release `v0.6`

#### Security

* `privileged: true` removed from `openvpn-ui` container — Docker socket mount is sufficient
* Admin credentials moved to `.env` file — no longer stored in `docker-compose.yml`
* Management interface now binds to `127.0.0.1` only instead of `0.0.0.0`
* `tls-auth pki/ta.key 0` added to `server.conf` — HMAC key is now enforced server-side
* RSA key size increased from 2048 to 4096 bit in `config/easy-rsa.vars`
* TLS minimum version raised from 1.2 to 1.3 in `config/client.conf`

> **Upgrading an existing installation?** See [CHANGELOG.md — PKI Migration](CHANGELOG.md#pki-migration) for instructions on activating `tls-auth` and the new key size without losing existing clients.

#### Improvements

* Healthchecks added to all containers in `docker-compose.yml` and `docker-compose-no-ui.yml`
* `openvpn-ui` now waits for `openvpn` to be healthy before starting (`condition: service_healthy`)
* `depends_on` direction corrected — `openvpn-ui` depends on `openvpn`, not the other way around
* `version` key removed from Compose files (deprecated since Docker Compose v2)
* `.env` added to `.gitignore`

#### Bugfixes

* Deprecated `openvpn --genkey --secret` replaced with `openvpn --genkey tls-auth` in `docker-entrypoint.sh`
* iptables ICMP rules fixed — added missing `-m icmp` match module in `docker-entrypoint.sh`
* All path variables in `backup.sh` properly quoted to handle paths with spaces
* Typo fixed: `"Generating ertificate authority"` → `"Generating certificate authority"` in `docker-entrypoint.sh`
* Log level reduced: `verb 4` → `verb 3` in `server.conf`

#### Dockerfile

* Base image pinned: `FROM alpine` → `FROM alpine:3.21`
* `ADD` replaced with `COPY` for `openssl-easyrsa.cnf`
* `ENTRYPOINT` changed from shell form to exec form for correct signal handling

---

### Release `v.0.5.1`

* Default OpenVPN Server configuration file has been moved from `/etc/openvpn/config` to `/etc/openvpn` directory.

### Release `v.0.4`

* Default Cipher for Server and Client configs is changed to `AES-256-GCM`
* **`ncp-ciphers`** option has been deprecated and replaced with **`data-ciphers`**
* 2FA support has been added

## Run this image

### Run image using a `docker-compose.yml` file

1. Clone the repo:

   ```shell
   git clone https://github.com/ozon08/openvpn-server
   ```

1. Create a `.env` file with your admin credentials (see [Credentials](#credentials)):

   ```shell
   cp .env.example .env
   ```

1. Start the containers:

   ```shell
   cd openvpn-server
   docker compose up -d
   ```

> **Note**: Before deploying, check the [Deployment Details](#container-deployment-details) section to configure all required variables.

For easy **OpenVPN Server** management install [**OpenVPN-UI**](https://github.com/ozon08/openvpn-ui).

## Container deployment details

### Credentials

Admin credentials are stored in a `.env` file that is **not committed to Git**. Create it before the first start:

```shell
OPENVPN_ADMIN_USERNAME=admin
OPENVPN_ADMIN_PASSWORD=your-secure-password
```

> **Important:** Change the default password before exposing the UI to any network.

### Docker-compose.yml

```yaml
---
services:
    openvpn:
       container_name: openvpn
       # To build your own image, uncomment the next line, comment "image:" and run "docker compose build"
       # build: .
       image: ozon08/openvpn-server:latest
       privileged: true
       ports:
          - "1194:1194/udp"   # openvpn UDP port
         # - "1194:1194/tcp"   # openvpn TCP port
         # - "2080:2080/tcp"  # management port. uncomment if you would like to share it with the host
       environment:
           TRUST_SUB: "10.0.70.0/24"
           GUEST_SUB: "10.0.71.0/24"
           HOME_SUB: "192.168.88.0/24"
       volumes:
           - ./pki:/etc/openvpn/pki
           - ./clients:/etc/openvpn/clients
           - ./config:/etc/openvpn/config
           - ./staticclients:/etc/openvpn/staticclients
           - ./log:/var/log/openvpn
           - ./fw-rules.sh:/opt/app/fw-rules.sh
           - ./checkpsw.sh:/opt/app/checkpsw.sh
           - ./server.conf:/etc/openvpn/server.conf
       cap_add:
           - NET_ADMIN
       restart: always
       healthcheck:
           test: ["CMD-SHELL", "echo '' > /dev/tcp/127.0.0.1/2080 2>/dev/null || exit 1"]
           interval: 30s
           timeout: 5s
           retries: 3
           start_period: 60s

    openvpn-ui:
       container_name: openvpn-ui
       image: ozon08/openvpn-ui:latest
       environment:
           - OPENVPN_ADMIN_USERNAME=${OPENVPN_ADMIN_USERNAME}
           - OPENVPN_ADMIN_PASSWORD=${OPENVPN_ADMIN_PASSWORD}
       ports:
           - "8080:8080/tcp"
       volumes:
           - ./:/etc/openvpn
           - ./db:/opt/openvpn-ui/db
           - ./pki:/usr/share/easy-rsa/pki
           - /var/run/docker.sock:/var/run/docker.sock:ro
       restart: always
       healthcheck:
           test: ["CMD", "wget", "-qO/dev/null", "http://localhost:8080"]
           interval: 30s
           timeout: 5s
           retries: 3
           start_period: 15s
       depends_on:
           openvpn:
               condition: service_healthy
```

**Where:**

* `TRUST_SUB` is Trusted subnet, from which OpenVPN server will assign IPs to trusted clients (default subnet for all clients)
* `GUEST_SUB` is Guest subnet for clients with internet access only
* `HOME_SUB` is subnet where the VPN server is located, through which you get internet access to the clients with MASQUERADE
* `fw-rules.sh` is a bash file with additional firewall rules you would like to apply during container start
* `checkpsw.sh` is a dummy bash script to use with `auth-user-pass-verify` option in `server.conf`. It is used to check user credentials against an external password DB, like LDAP, OATH, or MySQL. If you don't need this option, just leave it as is.

`docker_entrypoint.sh` will apply the following firewall rules:

```shell
IPT MASQ Chains:
MASQUERADE  all  --  10.0.70.0/24  anywhere
MASQUERADE  all  --  10.0.71.0/24  anywhere
IPT FWD Chains:
       0        0 DROP       icmp --  *      *       10.0.71.0/24  0.0.0.0/0  icmptype 8
       0        0 DROP       icmp --  *      *       10.0.71.0/24  0.0.0.0/0  icmptype 0
       0        0 DROP       all  --  *      *       10.0.71.0/24  192.168.88.0/24
```

Here is possible content of `fw-rules.sh` to apply additional rules:

```shell
iptables -A FORWARD -s 10.0.70.88 -d 10.0.70.77 -j DROP
iptables -A FORWARD -d 10.0.70.77 -s 10.0.70.88 -j DROP
```

<img src="https://github.com/d3vilh/raspberry-gateway/raw/master/images/OVPN_VLANs.png" alt="OpenVPN Subnets" width="700" border="1" />

Check the attached `docker-compose-no-ui.yml` file to run openvpn-server without the [OpenVPN UI](https://github.com/ozon08/openvpn-ui) container.

**Default EasyRSA** configuration can be changed in `~/openvpn-server/config/easy-rsa.vars` file:

```shell
set_var EASYRSA_DN           "org"
set_var EASYRSA_REQ_COUNTRY  "UA"
set_var EASYRSA_REQ_PROVINCE "KY"
set_var EASYRSA_REQ_CITY     "Kyiv"
set_var EASYRSA_REQ_ORG      "SweetHome"
set_var EASYRSA_REQ_EMAIL    "sweet@home.net"
set_var EASYRSA_REQ_OU       "MyOrganizationalUnit"
set_var EASYRSA_REQ_CN       "server"
set_var EASYRSA_KEY_SIZE     4096
set_var EASYRSA_CA_EXPIRE    3650
set_var EASYRSA_CERT_EXPIRE  825
set_var EASYRSA_CERT_RENEW   30
set_var EASYRSA_CRL_DAYS     180
```

> **Note:** Changes to `EASYRSA_KEY_SIZE` only take effect when generating a **new PKI**. Existing PKIs cannot be changed retroactively. See [CHANGELOG.md — PKI Migration](CHANGELOG.md#pki-migration) for upgrade instructions.

In the process of installation these vars will be copied to container volume `/etc/openvpn/pki/vars` and used during all EasyRSA operations.
You can update all these parameters later with OpenVPN UI on `Configuration > EasyRSA vars` page.

### Run with Docker

```shell
docker run --interactive --tty --rm \
  --name=openvpn \
  --cap-add=NET_ADMIN \
  -p 1194:1194/udp \
  -e TRUST_SUB=10.0.70.0/24 \
  -e GUEST_SUB=10.0.71.0/24 \
  -e HOME_SUB=192.168.88.0/24 \
  -v ./pki:/etc/openvpn/pki \
  -v ./clients:/etc/openvpn/clients \
  -v ./config:/etc/openvpn/config \
  -v ./staticclients:/etc/openvpn/staticclients \
  -v ./log:/var/log/openvpn \
  -v ./fw-rules.sh:/opt/app/fw-rules.sh \
  -v ./server.conf:/etc/openvpn/server.conf \
  --privileged ozon08/openvpn-server:latest
```

### Run the OpenVPN-UI image

```shell
docker run \
  -v /home/pi/openvpn-server:/etc/openvpn \
  -v /home/pi/openvpn-server/db:/opt/openvpn-ui/db \
  -v /home/pi/openvpn-server/pki:/usr/share/easy-rsa/pki \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e OPENVPN_ADMIN_USERNAME="${OPENVPN_ADMIN_USERNAME}" \
  -e OPENVPN_ADMIN_PASSWORD="${OPENVPN_ADMIN_PASSWORD}" \
  -p 8080:8080/tcp \
  ozon08/openvpn-ui:latest
```

> Credentials are read from your shell environment. Make sure to `export` them or source your `.env` file first.

### Build image from scratch

1. Clone the repo:

   ```shell
   git clone https://github.com/ozon08/openvpn-server
   ```

1. Build the image:

   ```shell
   cd openvpn-server
   docker build --force-rm=true -t ozon08/openvpn-server .
   ```

## Configuration

The volume container will be initialised with included scripts to automatically generate everything you need on the first run:

* Diffie-Hellman parameters
* an EasyRSA CA key and certificate
* a new private key
* a self-certificate matching the private key for the OpenVPN server
* a TLS auth key for HMAC security (enforced on both server and client)

This setup uses `tun` mode, as the most compatible with a wide range of devices. Note that `tun` does not work on macOS (without special workarounds) and on Android (unless rooted).

The topology used is `subnet`, for the same reasons. `p2p`, for instance, does not work on Windows.

The server config specifies `push redirect-gateway def1 bypass-dhcp`, meaning that after establishing the VPN connection, all traffic will go through the VPN. This might cause problems if you use local DNS recursors which are not directly reachable, since you will try to reach them through the VPN and they might not answer. If that happens, use public DNS resolvers like those of OpenDNS (`208.67.222.222` and `208.67.220.220`) or Google (`8.8.4.4` and `8.8.8.8`).

### OpenVPN Server directory structure

All server and client configuration is located in the mounted Docker volume and can be easily tuned:

```shell
|-- server.conf           # OpenVPN Server configuration file
|-- .env                  # Admin credentials (not committed to Git)
|-- clients
|   |-- your_client1.ovpn
|-- config
|   |-- client.conf
|   |-- easy-rsa.vars
|-- db
|   |-- data.db           # Optional OpenVPN UI DB
|-- log
|   |-- openvpn.log
|-- pki
|   |-- ca.crt
|   |-- certs_by_serial
|   |   |-- your_client1_serial.pem
|   |-- crl.pem
|   |-- dh.pem
|   |-- index.txt
|   |-- ipp.txt
|   |-- issued
|   |   |-- server.crt
|   |   |-- your_client1.crt
|   |-- openssl-easyrsa.cnf
|   |-- private
|   |   |-- ca.key
|   |   |-- your_client1.key
|   |   |-- server.key
|   |-- renewed
|   |   |-- certs_by_serial
|   |   |-- private_by_serial
|   |   |-- reqs_by_serial
|   |-- reqs
|   |   |-- server.req
|   |   |-- your_client1.req
|   |-- revoked
|   |   |-- certs_by_serial
|   |   |-- private_by_serial
|   |   |-- reqs_by_serial
|   |-- safessl-easyrsa.cnf
|   |-- serial
|   |-- ta.key
|-- staticclients          # Static client IP configuration files
```

### Generating .OVPN client profiles with [OpenVPN UI](https://github.com/ozon08/openvpn-ui)

You can access **OpenVPN UI** on its own port (*e.g. `http://localhost:8080`, change `localhost` to your public or private IPv4 address*). The default user and password are set via the `.env` file.

You can update the external client IP and port address anytime under `"Configuration > OpenVPN Client"` menu.

For this go to `"Configuration > OpenVPN Client"`:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-ext_serv_ip1.png" alt="Configuration > Settings" width="350" border="1" />

And then update `"Connection Address"` and `"Connection Port"` fields with your external Internet IP and port.

To generate a new Client Certificate go to `"Certificates"`, then press `"Create Certificate"` button, enter the new VPN client name, complete all the rest of the fields and press `"Create"` to generate a new client certificate:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-ext_serv_ip2.png" alt="Server Address" width="350" border="1" />  <img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-New_Client.png" alt="Create Certificate" width="350" border="1" />

To download the .OVPN client configuration file, press on the `Client Name` you just created:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-New_Client_download.png" alt="download OVPN" width="350" border="1" />

Install the [Official OpenVPN client](https://openvpn.net/vpn-client/) on your client device.

Deliver the .OVPN profile to the client device and import it as a FILE, then connect with the new profile:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Palm_import.png" alt="PalmTX Import" width="350" border="1" /> <img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Palm_connected.png" alt="PalmTX Connected" width="350" border="1" />

### Renew Certificates for client profiles

To renew a certificate, go to `"Certificates"` and press the `"Renew"` button for the client you would like to renew:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Cert-Renew.01.png" alt="Renew OpenVPN Certificate" width="600" border="1" />

Right after this step a new certificate will be generated and it will appear as a new client profile with the same client name. At this point both client profiles will have the updated certificate when you try to download it.

Once you deliver the new client profile with the renewed certificate to your client, press `"Revoke"` for the old profile to revoke the old certificate — the old profile will be deleted from the list.

If you still want to keep the old certificate, press `"Revoke"` on the new profile instead — the old certificate will be rolled back and the new profile will be deleted.

Renewal will not affect active VPN connections. The old client will be disconnected only after you revoke the old certificate or it expires.

### Revoking .OVPN profiles

To prevent a client from using your VPN connection, revoke the client certificate and restart the OpenVPN daemon.
You can do it via OpenVPN UI `"Certificates"` menu, by pressing the `"Revoke"` amber button:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Revoke.png" alt="Revoke Certificate" width="600" border="1" />

Certificate revocation won't kill active VPN connections — restart the service to immediately disconnect the user. This can be done from the same `"Certificates"` page by pressing the Restart red button:

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Restart.png" alt="OpenVPN Restart" width="600" border="1" />

You can do the same from the `"Maintenance"` page.

After revoking and restarting, the client will be disconnected and will not be able to connect again with the same certificate. To delete the certificate from the server, press the `"Remove"` button.

### OpenVPN client subnets — Guest and Home users

By default this OpenVPN server uses `server 10.0.70.0/24` as the **Trusted** subnet, from which all clients receive dynamic IPs and have full access to your **Private/Home** subnet as well as internet over VPN.

To share internet over VPN with specific **Guest** clients while restricting access to your **Private/Home** subnet, use the `route 10.0.71.0/24` option in `server.conf`.

<p align="center">
<img src="https://github.com/d3vilh/raspberry-gateway/blob/master/images/OVPN_VLANs.png" alt="OpenVPN Subnets" width="700" border="1" />
</p>

To assign a subnet policy to a specific client, define a static IP address during profile/certificate creation by filling in the `"Static IP (optional)"` field on the `"Certificates"` page.

> By default all clients have full access, so you don't need to configure a static IP for your own devices — they will always land in the **Trusted** subnet.

### CLI ways to manage the OpenVPN Server

**Generate** a new .OVPN profile (password is optional):

```shell
sudo docker exec openvpn bash /opt/app/bin/genclient.sh <name> <IP> <?password?>
```

You can find the .ovpn file under `/openvpn/clients/<name>.ovpn`. Make sure to check and modify the `remote ip-address`, `port` and `protocol`. It will also appear in the `"Certificates"` menu of OpenVPN UI.

**Revoke** an old .OVPN profile:

```shell
sudo docker exec openvpn bash /opt/app/bin/revoke.sh <clientname>
```

**Remove** an old .OVPN profile:

```shell
sudo docker exec openvpn bash /opt/app/bin/rmcert.sh <clientname>
```

**Restart** the OpenVPN container:

```shell
sudo docker restart openvpn
```

To define a static IP, go to the `~/openvpn/staticclients` directory and create a text file named after your client. Insert `ifconfig-push` with the desired static IP and mask:

```shell
echo "ifconfig-push 10.0.71.2 255.255.255.0" > ~/openvpn/staticclients/Slava
```

> By default all clients have full access, so you don't need to configure static IPs for your own devices.

### Screenshots of managing OpenVPN Server with OpenVPN UI

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Login.png" alt="OpenVPN-UI Login screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Home.png" alt="OpenVPN-UI Home screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Certs.png" alt="OpenVPN-UI Certificates screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Create-Cert.png" alt="OpenVPN-UI Create Certificate screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Certs-Details-Expire.png" alt="OpenVPN-UI Expire Certificate details" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Certs-Details_OK.png" alt="OpenVPN-UI OK Certificate details" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-EasyRsaVars.png" alt="OpenVPN-UI EasyRSA vars screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-EasyRsaVars-View.png" alt="OpenVPN-UI EasyRSA vars config view screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Maintenance.png" alt="OpenVPN-UI Maintenance screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Server-config.png" alt="OpenVPN-UI Server Configuration screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Server-config-edit.png" alt="OpenVPN-UI Server Configuration edit screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-ClientConf.png" alt="OpenVPN-UI Client Configuration screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Config.png" alt="OpenVPN-UI Configuration screen" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Profile.png" alt="OpenVPN-UI User Profile" width="1000" border="1" />

<img src="https://github.com/ozon08/openvpn-ui/blob/main/docs/images/OpenVPN-UI-Logs.png" alt="OpenVPN-UI Logs screen" width="1000" border="1" />

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/ozon)
