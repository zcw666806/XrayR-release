# XRayR
A Xray backend framework that can easily support many panels.

一个基于Xray的后端框架，支持V2ay,Trojan,Shadowsocks协议，极易扩展，支持多面板对接

Find the source code here: [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR)

# 详细使用教程

[教程](https://xrayr-project.github.io/XrayR-doc/)

# 一键安装

```
bash <(curl -Ls https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/install.sh)
```
# Docker 安装

```
docker pull ghcr.io/xrayr-project/xrayr:latest && docker run --restart=always --name xrayr -d -v ${PATH_TO_CONFIG}/config.yml:/etc/XrayR/config.yml --network=host ghcr.io/xrayr-project/xrayr:latest
```

适配v2board的本地化改造

```
1.config.yml

正确填好 V2Board 地址、ApiKey、NodeID
开启 EnableDNS: true、指定 dns/route/outbound 的路径

2.dns.json

按我给的模板：国内走 223.5.5.5，国外走 1.1.1.1 DoH，queryStrategy: UseIPv4

3.custom_outbound.json

先只放 direct + block 两个出口
以后要加 WARP/备用机场再扩展

4.route.json

正常情况直接用上面那套“国内直连，国外走 proxy”

5.custom_inbound.json

先留空数组 []

6.rulelist

暂时可以不用动；等你熟悉了再加审计规则。
```

# 分流配置基本理解
custom_outbound.json

这个版本假设你有：

warp：Cloudflare WARP 出站（socks 举例）
socks5-warp：本机 WARP Socks5 端口，用于特殊站点
IPv4_out：某条专门的代理线路（比如机场节点 A）
IPv6_out：自由直连走 IPv6，用于 Netflix 解锁
```
[
  {
    "tag": "direct",
    "protocol": "freedom",
    "settings": {
      "domainStrategy": "UseIPv4"
    }
  },
  {
    "tag": "block",
    "protocol": "blackhole",
    "settings": {
      "response": { "type": "http" }
    }
  },
  {
    // Cloudflare WARP：假设你本机有一个 warp socks5 端口 40000
    "tag": "warp",
    "protocol": "socks",
    "settings": {
      "servers": [
        {
          "address": "127.0.0.1",
          "port": 40000
        }
      ]
    }
  },
  {
    // WARP 的另一个 socks5 出口，用于特殊站点
    "tag": "socks5-warp",
    "protocol": "socks",
    "settings": {
      "servers": [
        {
          "address": "127.0.0.1",
          "port": 10800
        }
      ]
    }
  },
  {
    // 一个通过机场的 IPv4 节点（示意）
    "tag": "IPv4_out",
    "protocol": "vmess",
    "settings": {
      "vnext": [
        {
          "address": "your.server.com",
          "port": 443,
          "users": [
            {
              "id": "your-uuid",
              "alterId": 0,
              "security": "auto"
            }
          ]
        }
      ]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "serverName": "your.server.com"
      }
    }
  },
  {
    // 纯 IPv6 直连出口，用于 Netflix
    "tag": "IPv6_out",
    "protocol": "freedom",
    "settings": {
      "domainStrategy": "UseIPv6"
    }
  }
]

```
route.json

目标逻辑：

内网、BT → block
ChatGPT/OpenAI → socks5-warp（单独 WARP 出口）
Netflix → IPv6_out
国内域名/IP → warp（或 direct）
其它全部 → IPv4_out
```
{
  "domainStrategy": "IPIfNonMatch",
  "rules": [
    {
      "type": "field",
      "ip": [ "geoip:private" ],
      "outboundTag": "block"
    },
    {
      "type": "field",
      "protocol": [ "bittorrent" ],
      "outboundTag": "block"
    },
    {
      // ChatGPT / OpenAI 单独走 socks5-warp
      "type": "field",
      "domain": [
        "geosite:openai",
        "domain:chatgpt.com"
      ],
      "outboundTag": "socks5-warp"
    },
    {
      // Netflix 全部走 IPv6_out 出口（一般是解锁专线）
      "type": "field",
      "domain": [
        "geosite:netflix"
      ],
      "outboundTag": "IPv6_out"
    },
    {
      // 国内域名走 WARP（或 direct，看你需求）
      "type": "field",
      "domain": [
        "geosite:cn"
      ],
      "outboundTag": "warp"
    },
    {
      // 国内 IP 也走 WARP（补充上面）
      "type": "field",
      "ip": [
        "geoip:cn"
      ],
      "outboundTag": "warp"
    },
    {
      // 兜底：其它所有流量都走 IPv4_out（机场节点）
      "type": "field",
      "network": "tcp,udp",
      "outboundTag": "IPv4_out"
    }
  ]
}

```

这个配置的直观流向：

```
请求进来
  ├─ 内网 IP？           → block
  ├─ BT 协议？           → block
  ├─ ChatGPT/OpenAI？    → socks5-warp
  ├─ Netflix？           → IPv6_out
  ├─ 中国域名/IP？       → warp
  └─ 其它全部            → IPv4_out
```
