# nginx-vhost-wizard

An interactive Bash TUI that sets up a fully working **Nginx virtual host** in one command — SSL certificate included, signed by your own local Root CA.

```
    ╔═══════════════════════════════════════════════════════════════╗
    ║   🌐  E N V A Y S O F T   ·   N G I N X   V H O S T   ║
    ║        PHP-FPM  +  SSL signed by Envaysoft Root CA           ║
    ╚═══════════════════════════════════════════════════════════════╝
```

---

## What it does

One script, one run, everything configured:

| Step | What happens |
|------|-------------|
| **CA bootstrap** | Copies the Envaysoft Root CA into `/etc/ssl/envaysoft/` if not already present |
| **SSL certificate** | Generates a 2048-bit RSA key + CSR, signs it with the Root CA (SAN for domain, wildcard, and any aliases) |
| **Nginx config** | Writes a `sites-available` config with HTTP→HTTPS redirect, TLS 1.2/1.3, and app-specific routing |
| **Enable site** | Symlinks the config into `sites-enabled` and reloads Nginx |
| **Web root** | Creates the project directory and drops a starter `index.php` / `index.html` if empty |
| **/etc/hosts** | Optionally adds `127.0.0.1 yourdomain.local` (and aliases) |

---

## Requirements

- **OS**: Ubuntu / Debian (or any distro with `nginx` and `openssl` in `PATH`)
- **Nginx** installed and running
- **OpenSSL** (`openssl` CLI)
- **PHP-FPM** (optional — required for PHP profiles; auto-detected)
- `sudo` / root access

---

## Installation

```bash
git clone https://github.com/Al-Waleed-IT/-nginx-vhost-wizard.git
cd nginx-vhost-wizard
chmod +x create-vhost.sh
```

### Trust the Root CA (one-time setup)

So your browser stops showing SSL warnings for `*.local` domains:

**Ubuntu / Debian**
```bash
sudo cp envaysoft-ca.crt /usr/local/share/ca-certificates/envaysoft-ca.crt
sudo update-ca-certificates
```

**Chrome / Chromium** — go to `Settings → Privacy → Manage certificates → Authorities → Import`, select `envaysoft-ca.crt`, tick *Trust for websites*.

**Firefox** — go to `Settings → Privacy → View Certificates → Authorities → Import`.

---

## Usage

```bash
sudo ./create-vhost.sh
```

The script will re-execute itself with `sudo` if run without it.

### Interactive prompts

| Prompt | Example |
|--------|---------|
| Primary domain | `myapp.local` |
| Aliases | `api.myapp.local www.myapp.local` |
| Project directory | `/var/www/myapp` |
| Application type | see profiles below |
| Document root override | `/var/www/myapp/public` |
| PHP-FPM socket | auto-detected or manual path |
| Add to `/etc/hosts` | yes / no |

---

## Application profiles

| # | Profile | Document root | URL rewriting |
|---|---------|---------------|---------------|
| 1 | **Plain PHP** | project dir | `/index.php` fallback |
| 2 | **Laravel** | `project/public/` | Front controller, dotfile deny |
| 3 | **WordPress** | project dir | Permalink rewriting, upload PHP hardening |
| 4 | **Drupal** | `project/web/` | Clean URLs (D8/9/10), PATH_INFO support |
| 5 | **Static** | project dir | Static files only, no PHP |

---

## What gets created

```
/etc/ssl/envaysoft/
├── envaysoft-ca.crt        # Root CA certificate
├── envaysoft-ca.key        # Root CA private key (600)
├── myapp.local.key         # Site private key (600)
├── myapp.local.csr         # Certificate signing request
├── myapp.local.ext         # SAN extension file
└── myapp.local.crt         # Signed SSL certificate (644)

/etc/nginx/
├── sites-available/myapp.local   # Vhost config
└── sites-enabled/myapp.local     # Symlink → sites-available

/var/www/myapp.local/
└── index.php                     # Starter page (if directory was empty)

/etc/hosts
└── 127.0.0.1   myapp.local       # Added if requested
```

---

## Certificate details

- **Key**: RSA 2048-bit
- **Validity**: 825 days
- **SAN**: primary domain, `*.primary`, plus each alias and its wildcard
- **Signed by**: Envaysoft Root CA (ships with the repo)

---

## License

[MIT](LICENSE) © 2026 Al Waleed IT
