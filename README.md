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
config.yml

正确填好 V2Board 地址、ApiKey、NodeID

开启 EnableDNS: true、指定 dns/route/outbound 的路径

dns.json

按我给的模板：国内走 223.5.5.5，国外走 1.1.1.1 DoH，queryStrategy: UseIPv4

custom_outbound.json

先只放 direct + block 两个出口

以后要加 WARP/备用机场再扩展

route.json

正常情况直接用上面那套“国内直连，国外走 proxy”

custom_inbound.json

先留空数组 []

rulelist

暂时可以不用动；等你熟悉了再加审计规则。
```
