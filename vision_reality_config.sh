#!/bin/bash

author=Simon

# install base
install_base(){
  # Check if jq is installed, and install it if not
  if ! command -v jq &> /dev/null; then
      echo "jq is not installed. Installing..."
      if [ -n "$(command -v apt)" ]; then
          apt update > /dev/null 2>&1
          apt install -y jq > /dev/null 2>&1
      elif [ -n "$(command -v yum)" ]; then
          yum install -y epel-release
          yum install -y jq
      elif [ -n "$(command -v dnf)" ]; then
          dnf install -y jq
      else
          echo "Cannot install jq. Please install jq manually and rerun the script."
          exit 1
      fi
  fi
}

install_base

# Ask for server name (sni)
read -p "请输入想要使用的域名 (default: www.lovelive-anime.jp): " server_name
server_name=${server_name:-www.lovelive-anime.jp}
echo ""
# Ask for listen port
read -p "请输入Reality端口 (default: 51303): " listen_port
listen_port=${listen_port:-51303}

# generate private_key and public_key
key_pair=$(xray x25519)
echo "Key pair生成完成"
echo "$key_pair"
# Extract private key and public key
private_key=${key_pair:13:43}
public_key=${key_pair:69:43}
uuid=$(xray uuid)
short_id=$(openssl rand -hex 8)
echo "uuid和短id 生成完成"
echo ""
# 获取IP
server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)
# Ask link name
read -p "请输入连接别名 (default: D-R$server_ip): " link_name
link_name=${link_name:-D-R$server_ip}

# Create xray service config.json using jq
jq -n --arg uuid "$uuid" --arg listen_port $listen_port --arg server_name "$server_name" --arg server_name_post "$server_name:443" --arg private_key "$private_key" --arg short_id "$short_id" '{
    "log": {
        "loglevel": "warning"
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:cn",
                    "geoip:private"
                ],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": $listen_port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": $uuid,
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": $server_name_post,
                    "serverNames": [
                        $server_name
                    ],
                    "privateKey": $private_key,
                    "shortIds": [
                        $short_id
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}' > /usr/local/etc/xray/config.json

# 输出连接
echo "Vision Reality 客户端通用链接"
jq -n --arg uuid "$uuid" --arg listen_port "$listen_port" --arg server_name "$server_name" --arg server_ip "$server_ip" --arg public_key "$public_key" --arg short_id "$short_id" 'vless://$uuid@$server_ip:$listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#$link_name' > /usr/local/etc/xray/server_link.txt
echo ""
more /usr/local/etc/xray/server_link.txt
echo ""
# 重启Xray服务
echo "停止Xray服务"
systemctl stop xray
echo "启动Xray服务"
systemctl start xray
