🛡️ AWS 终极双擎双栈云管控制台 (Telegram Bot)

基于 Python 和 AWS Boto3 开发的全自动、免登录的 Telegram 机器人管理面板。无需进入繁琐的 AWS 网页端，即可在手机或电脑上优雅地对你的 AWS EC2 和 Lightsail 实例进行全生命周期管理。

独家攻克了 AWS 底层的多项痛点，包含：SSH 终端丢包截断修复、老旧环境 IPv6 资源池自动化构建、以及香港/台湾等隐藏区域（Opt-in Regions）的无缝探测与激活。

✨ 核心特性

🚀 双擎支持 (Lightsail & EC2)：在一个机器人内无缝切换产品线，统一管理。

🌍 双栈网络架构 (IPv4 + IPv6)：

开机即双栈：EC2/LS 创建时自动分配 IPv6。

智能 IPv6 资源池：针对旧版纯 IPv4 的 VPC 环境，脚本会自动向 AWS 申请 IPv6 CIDR，切割后挂载子网，全自动将老机器升级为双栈网络（独家技术）。

独立换 IP：一键更换受污染的 IPv4 或重新分配 IPv6。

🔓 全球隐藏区域激活：

绕过复杂的控制台，内置官方 AWS CLI 引擎探测 not-opted-in 的隐藏区域（如 ap-east-1 香港, ap-northeast-4 台湾）。

一键下发 enable-region 激活指令。

🛡️ 双栈防火墙管理：

自定义端口或一键全开。

规则下发时自动同时对 IPv4 (0.0.0.0/0) 和 IPv6 (::/0) 生效。

🔒 极致安全与稳定：

密钥安全：AK/SK 完全存储于本地 lightsail_accounts.json，绝不上传第三方。

鉴权机制：严格绑定指定的 Telegram User ID，其他人向机器人发消息完全无视。

垂直排版防截断：所有代码经过单行长度压缩，彻底杜绝 SSH 终端因剪贴板溢出导致的语法报错。

物理急救：内置“一键杀僵尸进程”工具，专治因 AWS API 延迟导致的 Bot 卡死假死。

🛠️ 部署指南

环境要求

一台 Linux 服务器（Ubuntu / Debian / CentOS）。

拥有公网 IP（推荐使用闲置的海外 VPS 部署以确保 Telegram API 连通性）。

一个 Telegram Bot Token（向 @BotFather 申请）。

你的 Telegram User ID（向 @userinfobot 获取）。

一键安装 / 更新

无需繁琐的依赖配置，只需在终端中执行以下命令（复制粘贴完整脚本内容并运行）：

# 下载或新建 aws_toolkit.sh 文件
# 复制本文仓库中的 aws_toolkit.sh 代码放入其中
bash aws_toolkit.sh


运行后将出现交互式菜单：

=======================================================
   🛡️ AWS 终极双擎双栈云管控制台 v3.6 (GitHub开源版)
=======================================================

请选择操作：
 [1] 部署/重置 机器人主程序 (保留本地数据)
 [2] 扫描并激活 AWS 全球隐藏区域
 [3] 退出工具箱
 [4] 物理急救 (修复机器人卡死/无响应)


输入 1 即可全自动拉取依赖、配置守护进程 (Systemd) 并启动机器人。
更新脚本或代码时，直接再次运行 bash aws_toolkit.sh 并选 1 即可，本地账号配置 (JSON) 将被安全继承，绝不会丢失。

📖 避坑指南：关于 Lightsail 与“隐藏区域”

这是在开发中摸索出的极其重要的 AWS 底层机制：

EC2 纯享版自动化：如果你只开通 EC2，通过脚本（选项2）激活了香港等隐藏区域后，可以直接在 Telegram 中开机，全程无需登录网页端。

Lightsail 的惰性初始化 (Lazy Initialization)：
如果你要在新激活的区域（如香港）开 Lightsail，AWS API 经常会报错 RegionSetupInProgressException 并且无限期卡死。

解决办法：这是一个“一次性激活税”。请登录 AWS 网页端控制台，进入 Lightsail 面板，将区域切换到该隐藏区域（如 Hong Kong）看一眼。网页前端会强制触发 AWS 后台的高优先级环境初始化（为你搭建默认 VPC 和服务角色）。

结果：点一下网页后，直接关掉浏览器。以后这辈子你都可以通过 Telegram 机器人秒开 Lightsail 了！

📝 许可证 (License)

本项目基于 MIT License 开源。您可以自由地使用、修改和分发，但请保留原作者归属。
