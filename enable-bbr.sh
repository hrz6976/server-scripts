#!/bin/sh

# enable bbr

# check am i root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# check if bbr is enabled
if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control ; then
    echo "BBR is already enabled."
    exit 0
fi

# enable bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# check if bbr is enabled
if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control ; then
    echo "BBR is enabled."
    exit 0
else
    echo "Failed to enable BBR."
    exit 1
fi