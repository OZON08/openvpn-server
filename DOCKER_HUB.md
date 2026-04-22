# ozon08/openvpn-server

Fast Docker container with OpenVPN Server living inside.

> Forked from [d3vilh/openvpn-server](https://github.com/d3vilh/openvpn-server) with security hardening, updated dependencies, and improved Docker configuration.

## Quick Start

```shell
git clone https://github.com/ozon08/openvpn-server
cd openvpn-server
cp .env.example .env        # add your admin credentials
docker compose up -d
```

## Environment variables

| Variable | Description |
| --- | --- |
| `TRUST_SUB` | Trusted subnet — full access to home network and internet (default: `10.0.70.0/24`) |
| `GUEST_SUB` | Guest subnet — internet only, no access to home network (default: `10.0.71.0/24`) |
| `HOME_SUB` | Your home/private subnet (default: `192.168.88.0/24`) |

Admin credentials (`OPENVPN_ADMIN_USERNAME`, `OPENVPN_ADMIN_PASSWORD`) are stored in a `.env` file — never hardcoded in `docker-compose.yml`.

## Volumes

| Path | Description |
| --- | --- |
| `./pki` | PKI certificates and keys |
| `./clients` | Generated `.ovpn` client profiles |
| `./config` | EasyRSA vars and client config template |
| `./staticclients` | Static IP assignments per client |
| `./log` | OpenVPN log files |
| `./server.conf` | OpenVPN server configuration |

## Security highlights (v0.6.2)

- `tls-auth` enforced server-side — packets without valid HMAC are dropped
- Management interface binds to `127.0.0.1` only
- No `privileged` mode for the UI container
- RSA key size 4096 bit
- TLS minimum version 1.3 for clients
- Admin credentials stored in `.env`, excluded from Git

## Ports

| Port | Protocol | Description |
| --- | --- | --- |
| `1194` | UDP | OpenVPN |
| `8080` | TCP | OpenVPN UI (optional) |

## Links

- [GitHub Repository](https://github.com/ozon08/openvpn-server)
- [OpenVPN UI](https://github.com/ozon08/openvpn-ui)
- [Changelog](https://github.com/ozon08/openvpn-server/blob/main/CHANGELOG.md)
- [PKI Migration Guide](https://github.com/ozon08/openvpn-server/blob/main/CHANGELOG.md#pki-migration)
