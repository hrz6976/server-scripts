#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker before running this script."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install jq before running this script."
    exit 1
fi

# Check if the Docker daemon configuration file exists
if [ ! -f /etc/docker/daemon.json ]; then
    # Create the configuration file if it doesn't exist
    echo '{}' | sudo tee /etc/docker/daemon.json
fi

if grep -q "ipv6" /etc/docker/daemon.json ; then
    echo "IPv6 is already enabled."
    exit 0
fi

# Add IPv6 support, ip6tables, and experimental settings using jq
sudo cat /etc/docker/daemon.json | jq '. + { "ipv6": true, "fixed-cidr-v6": "2001:db8:1::/64", "ip6tables": true, "experimental": true }' | sudo tee /etc/docker/daemon.json

# Restart Docker
sudo systemctl restart docker
