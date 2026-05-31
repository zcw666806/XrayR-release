# XRayR 自托管发布仓库

本仓库用于在原上游发布地址不可用时，自行托管 XrayR 安装脚本、管理脚本、systemd 服务、配置模板和 XrayR 二进制 Release。

## 一键安装

```bash
bash <(curl -fLs https://raw.githubusercontent.com/zcw666806/XrayR-release/master/install.sh)
```

安装脚本将从本仓库读取所有内容：

- 从 GitHub Releases API 获取本仓库的最新 tag；
- 从本仓库 Release 下载与 CPU 架构匹配的 XrayR ZIP；
- 从 `master` 分支下载 `XrayR.service`、`XrayR.sh` 和 `config/` 中的模板；
- 全新安装时将模板复制到 `/etc/XrayR/`；
- 更新时保留服务器已有的可编辑配置，只刷新 `geoip.dat` 和 `geosite.dat`。

## 首次使用前必须准备的 Release

仅仅备份 Git 仓库还不够。执行一键安装前，必须在本仓库的 **Releases** 页面创建至少一个 GitHub Release，例如 tag 为 `0.9.5`，并上传目标服务器架构对应的 ZIP 文件。当前脚本不携带 GitHub Token，因此 `master` 分支和 Release 资产必须允许公开下载；如果仓库是私有仓库，需要另外增加鉴权逻辑。

脚本支持以下资产文件名：

| 服务器架构 | Release 资产文件名 |
| --- | --- |
| x86_64 / amd64 | `XrayR-linux-64.zip` |
| arm64 / aarch64 | `XrayR-linux-arm64-v8a.zip` |
| s390x | `XrayR-linux-s390x.zip` |

每个 ZIP 的**根目录**至少必须包含编译好的可执行文件：

```text
XrayR
```

配置文件不需要放入 ZIP。安装器会直接从本仓库 `config/` 目录下载：

```text
config/config.yml
config/dns.json
config/route.json
config/custom_outbound.json
config/custom_inbound.json
config/rulelist
config/geoip.dat
config/geosite.dat
```

如果只部署 x86_64 服务器，最少只需上传 `XrayR-linux-64.zip`。如果需要兼容多种 CPU，则为每种架构分别上传对应文件。

## 发布和安装步骤

1. 将自行备份或编译得到的 `XrayR` 可执行文件按目标架构打包。例如 x86_64：

   ```bash
   zip XrayR-linux-64.zip XrayR
   ```

2. 在 `zcw666806/XrayR-release` 仓库创建 GitHub Release，例如 `0.9.5`，上传 `XrayR-linux-64.zip`。
3. 将本仓库 `master` 分支推送到 GitHub。
4. 在服务器执行一键安装命令。
5. 首次安装完成后，编辑服务器上的配置文件：

   ```bash
   vi /etc/XrayR/config.yml
   ```

6. 至少将 `ApiHost`、`ApiKey` 和各节点的 `NodeID` 改成实际值，然后启动并检查日志：

   ```bash
   XrayR start
   XrayR status
   XrayR log
   ```

## 使用 GitHub Actions 自动生成并上传 Release 资产

仓库已包含工作流 `.github/workflows/build-xrayr-release.yml`。它会从 `zcw666806/XrayR` 读取 Go 源码，交叉编译 Linux `amd64`、`arm64` 和 `s390x` 三种架构，生成安装器需要的 ZIP 文件，并上传到已经存在的 Release。

如果 `zcw666806/XrayR` 是公开仓库，无需额外 Token。如果它是私有仓库，请先在 `zcw666806/XrayR-release` 的 **Settings → Secrets and variables → Actions** 中添加名为 `XRAYR_SOURCE_TOKEN` 的 fine-grained personal access token，并至少授予读取 `zcw666806/XrayR` 内容的权限。默认 `GITHUB_TOKEN` 通常不能读取另一个私有仓库。

您已经建立 `0.9.5` Release 后，可以在 `zcw666806/XrayR-release` 的 **Actions → Build and upload XrayR release assets → Run workflow** 中填写：

```text
release_tag:       0.9.5
source_repository: zcw666806/XrayR
source_ref:        master
```

工作流成功后，`0.9.5` Release 应包含：

```text
XrayR-linux-64.zip
XrayR-linux-64.zip.sha256
XrayR-linux-arm64-v8a.zip
XrayR-linux-arm64-v8a.zip.sha256
XrayR-linux-s390x.zip
XrayR-linux-s390x.zip.sha256
```

如果您希望在自己的 Linux 电脑上手动生成这些文件，也可以将源码仓库与本仓库放在相邻目录，然后执行：

```bash
./scripts/build-release-assets.sh ../XrayR ./dist
```

脚本只会将编译得到的 `XrayR` 可执行文件放入 ZIP。配置模板仍由安装器从本仓库 `config/` 目录下载。

## 配置更新策略

- `config.yml`、`dns.json`、`route.json`、`custom_outbound.json`、`custom_inbound.json` 和 `rulelist` 只会在服务器上不存在时安装，避免 `XrayR update` 覆盖线上配置。
- `geoip.dat` 和 `geosite.dat` 会在每次安装或更新时同步为仓库中的版本。
- 如果希望强制应用新的模板，请先备份并删除服务器上对应的 `/etc/XrayR/` 文件，再重新执行安装。

## 安全注意事项

`config/config.yml` 会通过公开 Raw URL 下载，因此仓库中的模板只能保存占位符，不能提交真实的面板地址、`ApiKey`、UUID 或其他凭据。首次安装后请只在服务器的 `/etc/XrayR/config.yml` 中填写真实值。

如果旧提交曾经包含真实 `ApiKey`，即使当前文件已改成占位符，也应立即在面板中轮换旧密钥；Git 历史仍可能保留旧值。

管理菜单中的 BBR 安装功能仍会执行第三方 `chiakge/Linux-NetSpeed` 脚本。该功能不属于 XrayR 安装链路；如果要求所有远程脚本完全自托管，请先审查、fork 并替换该链接，或不要使用该菜单项。

## 指定版本更新

```bash
XrayR update          # 交互式选择版本，留空表示最新版
XrayR update 0.9.5    # 安装 Release tag 0.9.5；指定版本会按输入的 tag 原样下载
```

## 适配 V2Board 的本地化配置

1. `config.yml`：填写 V2Board 地址、`ApiKey`、`NodeID`，并按需指定 DNS、路由和出站路径。
2. `dns.json`：按模板配置 DNS。
3. `custom_outbound.json`：按实际环境配置 direct、block、WARP 或其他出口。
4. `route.json`：按实际环境调整分流规则。
5. `custom_inbound.json`：不需要自定义入站时保留空数组 `[]`。
6. `rulelist`：按需添加审计规则。

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
