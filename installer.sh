#!/usr/bin/env bash
set -eu

# Check the OS
platform="$(uname | tr '[:upper:]' '[:lower:]')"
if [[ "$platform" != "linux" && "$platform" != "darwin" ]]; then
    echo "You seem to be running on an unsupported platform, the installer"
    echo "will only work on Linux and MacOS."
    exit 123
fi
distro="$(lsb_release -is 2>/dev/null || true)"
distro="${distro:-unknown}"

# Seed secrets
RELEASE_COOKIE=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 30)
SESSION_KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 64)
JUMPWIRE_ENCRYPTION_KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 64)

# Talk to the user
echo "Welcome to the single instance JumpWire installer"
echo ""
echo "Let's first start by getting the exact domain JumpWire will be installed on"
echo "Make sure that you have a Host A DNS record pointing to this instance!"
echo "This will be used for TLS"
echo "ie: test.example.com"
read -erp "Domain: " DOMAIN
echo "Ok we'll set up certs for https://$DOMAIN"
echo ""
echo "Next, we need the token that provided to you for this installation. This token"
echo "is unique to you and should be treated like a password"
read -erp "Token: " ORG_TOKEN
echo ""
echo "Which email domains should logins be restricted to? If you have multiple domains,"
echo "enter them as a single value separated with commas"
echo "ie: example.com,example.net"
read -erp "Allowed domains: " -i "${DOMAIN#*.}" JUMPWIRE_AUTH_DOMAINS
echo ""
echo "Finally, we'll need the credentials for logging in with Google OAuth."
echo "If you have not yet setup an OAuth client for JumpWire, follow these"
echo "instructions before continuing:"
echo "https://support.google.com/cloud/answer/6158849?hl=en"
read -erp "Google Client ID: " GOOGLE_CLIENT_ID
read -erp "Google Client Secret: " GOOGLE_CLIENT_SECRET
echo ""
echo "Ok! We'll take it from here"

function is_bin_in_path {
  builtin type -P "$1" &> /dev/null
}

mkdir -p .bin
PATH="${PATH}:$(pwd)/.bin"

# preflight checks
echo "Checking for docker..."
docker version >/dev/null
echo "Ok!"

echo "Checking for docker-compose..."
if ! is_bin_in_path docker-compose; then
    echo "docker-compose not found, trying to download it..."
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o .bin/docker-compose
    chmod +x .bin/docker-compose
fi
docker-compose version >/dev/null
echo "Ok!"

echo "Checking for jq..."
if ! is_bin_in_path jq; then
    echo "jq not found, trying to download it..."
    case $platform in
        linux)
            curl -L -o .bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
            ;;
        darwin)
            curl -L -o .bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64
            ;;
        *)
            ;;
    esac
    chmod +x .bin/jq
fi
jq --version >/dev/null
echo "Ok!"

# parse the org id from the subject of the JWT token. the token won't actually be validated
# yet, that will only happen once the cluster attempts to start.
ORG_ID=$(echo $ORG_TOKEN | jq -R 'split(".") | .[1] | @base64d | fromjson | .sub' -r)

# configure caddy to act as a reverse proxy
cat > Caddyfile <<EOF
${DOMAIN} {
  reverse_proxy web:4000
}

hook.${DOMAIN} {
  reverse_proxy engine:4001
}
EOF

# create environment variable files
cat > engine.env <<EOF
RELEASE_COOKIE=${RELEASE_COOKIE}
JUMPWIRE_ENCRYPTION_KEY=${JUMPWIRE_ENCRYPTION_KEY}
JUMPWIRE_ORG_TOKEN=${ORG_TOKEN}
EOF

cat > web.env <<EOF
JUMPWIRE_DOMAIN=${DOMAIN}
JUMPWIRE_SESSION_KEY=${SESSION_KEY}
JUMPWIRE_AUTH_DOMAINS=${JUMPWIRE_AUTH_DOMAINS}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
JUMPWIRE_ORG_ID=${ORG_ID}
JUMPWIRE_ORG_TOKEN=${ORG_TOKEN}
EOF

echo "Making sure any stack that might exist is stopped..."
docker-compose stop || true

echo "Fetching the JumpWire docker compose file from GitHub..."
#rm -f docker-compose.yaml
#curl -o docker-compose.yaml https://raw.githubusercontent.com/extragood-io/jumpwire-deployment/main/docker-compose.yaml

# send log of this install for continued support!
curl -L -H "Content-Type: application/json" https://events.jumpwire.ai/capture/ -d @- <<EOF
{
  "api_key": "phc_KSCQEEHeUZhMwHaFOOdA4OCf5vaxAsuSMWuRbbcsk5H",
  "properties": {"distinct_id": "${DOMAIN}", "platform": "${platform}", "distro": "${distro}"},
  "event": "magic_curl_install"
}
EOF

# start up the stack
echo "Running database migrations..."
docker-compose run web eval Gamayun.Release.migrate &>> migrations.log

echo "Starting the JumpWire stack..."
docker-compose up -d

echo "We will need to wait a few minutes for things to settle down, migrations to finish, and TLS certs to be issued"
echo ""
echo "Waiting for JumpWire web to boot (this will take a few minutes)"
bash -c 'while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost:4000/api/ping)" != "200" ]]; do sleep 5; done'
echo "JumpWire looks up!"
echo ""
echo "Done!"
echo ""
echo "To stop the stack run 'docker-compose stop'"
echo "To start the stack again run 'docker-compose start'"
echo "If you have any issues at all delete everything in this directory and run the curl command again"
echo ""
echo "JumpWire will be up at the location you provided!"
echo "https://${DOMAIN}"
echo ""
