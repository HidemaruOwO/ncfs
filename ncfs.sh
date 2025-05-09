#!/bin/bash

# Copyright © 2023 Barış DEMİRCİ <hi@338.rocks>
# SPDX-License-Identifier: GPL-3.0

echo "🚀 NCFS: Starting NGROK to Cloudflare Forwarding Script..."

# Checking dependencies
echo "🔍 NCFS: Checking dependencies..."

apt_dependencies=()
snap_dependencies=()
is_passed_other_snap=true

# Check if snap is installed. If not, install it.
echo "🔍 DEPENDENCIES: Checking if snap is installed..."

if ! command -v snap &>/dev/null; then
	echo "❌ DEPENDENCIES: snap could not be found"
	echo "⬇️ DEPENDENCIES: Installing snap..."

	apt_dependencies+=("snapd")
fi

# Check if ngrok is installed. If not, install it.
echo "🔍 DEPENDENCIES: Checking if ngrok is installed..."

if ! command -v ngrok &>/dev/null; then
	echo "❌ DEPENDENCIES: ngrok could not be found"
	echo "⬇️ DEPENDENCIES: Installing ngrok..."

	is_passed_other_snap=false
	snap_dependencies+=("ngrok")
fi

# Check if curl is installed. If not, install it.
echo "🔍 DEPENDENCIES: Checking if curl is installed..."

if ! command -v curl &>/dev/null; then
	echo "❌ DEPENDENCIES: curl could not be found"
	echo "⬇️ DEPENDENCIES: Installing curl..."

	is_passed_other_snap=false
	apt_dependencies+=("curl")
fi

# Check if jq is installed. If not, install it.
echo "🔍 DEPENDENCIES: Checking if jq is installed..."

if ! command -v jq &>/dev/null; then
	echo "❌ DEPENDENCIES: jq could not be found"
	echo "⬇️ DEPENDENCIES: Installing jq..."

	is_passed_other_snap=false
	apt_dependencies+=("jq")
fi

join() {
	local IFS="$1"
	shift
	echo "$*"
}

snap_command=""
apt_command=""

if [ ${#snap_dependencies[@]} -gt 0 ]; then
	snap_command="snap install $(join "${snap_dependencies[@]}")"
fi

if [ ${#apt_dependencies[@]} -gt 0 ]; then
	apt_command="sudo apt install -y $(join "${apt_dependencies[@]}")"
fi

install_dependencies() {
	sudo apt update
	sudo snap refresh

	if [ ! -z "$snap_command" ]; then
		echo "⬇️ DEPENDENCIES: Installing snap dependencies..."

		eval "$snap_command"
	fi

	if [ ! -z "$apt_command" ]; then
		echo "⬇️ DEPENDENCIES: Installing apt dependencies..."

		eval "$apt_command"
	fi

	echo "✅ DEPENDENCIES: Dependencies installed successfully"
}

# if snap command or apt command is not empty, ask user if they want to install dependencies
if ! $is_passed_other_snap; then
	if [ ! -z "$snap_command" ] || [ ! -z "$apt_command" ]; then
		read -p "🚀 DEPENDENCIES: Would you like to install missing dependencies? [y/N] " install

		case $install in
		[Yy]*)
			install_dependencies
			break
			;;
		*)
			echo "❌ DEPENDENCIES: Operation cancelled, exiting..."
			exit 1
			;;
		esac
	fi
fi

NGROK_TCP_PORT=$(jq -r .NGROK_TCP_PORT config.json)
NGROK_AUTH_TOKEN=$(jq -r .NGROK_AUTH_TOKEN config.json)
CLOUDFLARE_AUTH_EMAIL=$(jq -r .CLOUDFLARE_AUTH_EMAIL config.json)
CLOUDFLARE_API_KEY=$(jq -r .CLOUDFLARE_API_KEY config.json)
CLOUDFLARE_ZONE_ID=$(jq -r .CLOUDFLARE_ZONE_ID config.json)
CLOUDFLARE_CNAME_RECORD_NAME=$(jq -r .CLOUDFLARE_CNAME_RECORD_NAME config.json)
CLOUDFLARE_SRV_RECORD_NAME=$(jq -r .CLOUDFLARE_SRV_RECORD_NAME config.json)

# Checking cloudflare config
echo "🔍 NCFS: Checking Cloudflare config..."

# Get CNAME record from Cloudflare
echo "🔍 CF Checker: Getting CNAME record from Cloudflare..."

cname_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$CLOUDFLARE_CNAME_RECORD_NAME" \
	-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
	-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
	-H "Content-Type: application/json")

# Check if record exists
if [[ $cname_record == *"\"count\":0"* ]]; then
	echo "❌ CF Checker: CNAME record does not exist in Cloudflare. You have to create it manually. Create a CNAME record in your Cloudflare dashboard and set the name to $CLOUDFLARE_CNAME_RECORD_NAME (you can put example.com to content for now)"
	exit 1
fi

# Get CNAME record id
cname_record_id=$(echo "$cname_record" | sed -E 's/.*"id":"(\w+)".*/\1/')

# Get SRV record from Cloudflare
echo "🔍 CF Checker: Getting SRV record from Cloudflare..."

srv_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=SRV&name=_minecraft._tcp.$CLOUDFLARE_SRV_RECORD_NAME" \
	-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
	-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
	-H "Content-Type: application/json")

# Check if record exists
if [[ $srv_record == *"\"count\":0"* ]]; then
	echo "❌ CF Checker: SRV record does not exist in Cloudflare. You have to create it manually. Create a SRV record in your Cloudflare dashboard and set the name to $CLOUDFLARE_SRV_RECORD_NAME (you can put $CLOUDFLARE_CNAME_RECORD_NAME to content for now)"
	exit 1
fi

# Get SRV record id
srv_record_id=$(echo "$srv_record" | sed -E 's/.*"id":"(\w+)".*/\1/')

# Starting ngrok
echo "🚀 NCFS: Starting NGROK..."

# Set NGROK auth token
echo "🔑 NGROK: Setting NGROK auth token..."

ngrok config add-authtoken $NGROK_AUTH_TOKEN

# Run NGROK on background
echo "🚀 NGROK: Starting NGROK on background..."

if [ -z "$DOCKER_MC_NETWORK" ]; then
	ngrok tcp 127.0.0.1:$NGROK_TCP_PORT >/dev/null &
else
	ngrok tcp $DOCKER_MC_NETWORK:$NGROK_TCP_PORT >/dev/null &
fi

# Wait for NGROK to start
echo "🕑 NGROK: Waiting for NGROK to start..."

while ! curl -s localhost:4040/api/tunnels | grep -q "tcp://"; do
	sleep 1
done

echo "✅ NGROK: NGROK started successfully"

# Get NGROK URL
echo "🔗 NGROK: Getting NGROK URL..."

ngrok_url=$(curl -s localhost:4040/api/tunnels | grep -o "tcp://[0-9a-z.-]*:[0-9]*")
parsed_ngrok_url=${ngrok_url/tcp:\/\//}

IFS=':' read -ra ADDR <<<"$parsed_ngrok_url"
ngrok_host=${ADDR[0]}
ngrok_port=${ADDR[1]}

# Log NGROK URL
echo "🔗 NGROK: URL: $ngrok_url"
echo "🔗 NGROK: Parsed URL: $parsed_ngrok_url"
echo "🔗 NGROK: Host and Port: $ngrok_host - $ngrok_port"

# Update Cloudflare records
echo "📝 NCFS: Updating Cloudflare records..."

# Update CNAME record
echo "📝 CF Updater: Updating CNAME record..."

update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$cname_record_id" \
	-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
	-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
	-H "Content-Type: application/json" \
	--data "{\"type\":\"CNAME\",\"name\":\"$CLOUDFLARE_CNAME_RECORD_NAME\",\"content\":\"$ngrok_host\"}")

# Check if update is successful
case "$update" in
*"\"success\":false"*)
	echo "❌ CF Updater: CNAME record could not be updated in Cloudflare. $update"
	exit 1
	;;
*)
	echo "✅ CF Updater: CNAME record updated in Cloudflare. $ngrok_host - $CLOUDFLARE_CNAME_RECORD_NAME"
	;;
esac

# Update SRV record
echo "📝 CF Updater: Updating SRV record..."

update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$srv_record_id" \
	-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
	-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
	-H "Content-Type: application/json" \
	--data "{\"type\":\"SRV\",\"name\":\"_minecraft._tcp.$CLOUDFLARE_SRV_RECORD_NAME\",\"data\": {\"name\":\"$CLOUDFLARE_SRV_RECORD_NAME\",\"port\":$ngrok_port,\"proto\":\"_tcp\",\"service\":\"_minecraft\",\"target\":\"$CLOUDFLARE_CNAME_RECORD_NAME\"}}")

# Check if update is successful
case "$update" in
*"\"success\":false"*)
	echo "❌ CF Updater: SRV record could not be updated in Cloudflare. $update"
	exit 1
	;;
*)
	echo "✅ CF Updater: SRV record updated in Cloudflare. $ngrok_host - _minecraft._tcp.$CLOUDFLARE_SRV_RECORD_NAME"
	;;
esac

# Done! Exit gracefully
echo "✅ NCFS: Done (Press Ctrl-C then kill ngrok and ncfs)"

tail -f "/dev/null"

exit 0
