#!/bin/bash

ACCOUNTS_FILE="/root/lightsail_accounts.json"
BOT_SCRIPT="/root/lightsail_master_bot.py"
SERVICE_FILE="/etc/systemd/system/lightsail-bot.service"

deploy_bot() {
echo -e "\n======================================================="
echo " 🚀 [1/4] 启动智能环境检测..."
echo "======================================================="

if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
    echo "⏳ 未检测到 Python3，正在自动安装..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y python3 python3-pip >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y python3 python3-pip >/dev/null 2>&1
    fi
fi

pip3 install -q pyTelegramBotAPI requests boto3

if [ -f "$SERVICE_FILE" ]; then
    INPUT_TOKEN=$(grep -oP 'TG_BOT_TOKEN=\K[^"\n]+' "$SERVICE_FILE" | head -n 1)
    INPUT_ID=$(grep -oP 'TG_USER_ID=\K[^"\n]+' "$SERVICE_FILE" | head -n 1)
    echo "✅ 沿用历史 Token: ${INPUT_TOKEN:0:5}***  \vert{}  ID:$INPUT_ID"
else
    read -p "🔑 输入 Telegram Bot Token: " INPUT_TOKEN
    read -p "👤 输入 Telegram User ID (纯数字): " INPUT_ID
    if [ -z "$INPUT_TOKEN" ] \vert{}\vert{} [ -z "$INPUT_ID" ]; then
        echo "❌ 参数缺失，终止部署。"
        return
    fi
fi

echo -e "\n======================================================="
echo " ⚙️ [3/4] 注入核心代码 (极限短行防截断模式)..."
echo "======================================================="
systemctl stop lightsail-bot > /dev/null 2>&1


cat > $BOT_SCRIPT << 'EOF_PYTHON'
import os, sys, time, json, random
import datetime, requests, telebot, boto3
from telebot.types import InlineKeyboardMarkup
from telebot.types import InlineKeyboardButton

TG_BOT_TOKEN = os.environ.get('TG_BOT_TOKEN', '').strip()
try:
TG_USER_ID = int(os.environ.get('TG_USER_ID', '0').strip())
except:
TG_USER_ID = 0

ALLOWED_USERS = [TG_USER_ID]
ACCOUNTS_FILE = '/root/lightsail_accounts.json'
bot = telebot.TeleBot(TG_BOT_TOKEN)
bot.remove_webhook()
user_state = {}
GLOBAL_SEQ = 0

def get_seq():
global GLOBAL_SEQ
GLOBAL_SEQ = (GLOBAL_SEQ % 99) + 1
return GLOBAL_SEQ

REGION_CODES = {
'ap-northeast-1': 'JP', 'ap-northeast-2': 'KR',
'ap-northeast-3': 'JP', 'ap-northeast-4': 'TW',
'ap-east-1': 'HK', 'ap-southeast-1': 'SG',
'ap-southeast-2': 'AU', 'ap-south-1': 'IN',
'us-east-1': 'US', 'us-east-2': 'US',
'us-west-1': 'US', 'us-west-2': 'US',
'eu-central-1': 'DE', 'eu-west-1': 'IE',
'eu-west-2': 'GB', 'eu-west-3': 'FR',
'ca-central-1': 'CA'
}

PORTS_DICT = {
'80': 'HTTP', '443': 'HTTPS', '3306': 'MySQL',
'6379': 'Redis', '8888': '宝塔', 'ICMP': 'Ping'
}

def load_accounts():
try:
if not os.path.exists(ACCOUNTS_FILE): return {}
with open(ACCOUNTS_FILE, 'r') as f:
return json.load(f)
except:
return {}

def save_accounts(accounts):
with open(ACCOUNTS_FILE, 'w') as f:
json.dump(accounts, f, indent=4)

def is_allowed(m):
uid = m.chat.id if hasattr(m, 'chat') else m.from_user.id
return int(uid) in ALLOWED_USERS

def get_boto_client(service, chat_id, region_name=None):
acc_id = user_state.get(chat_id, {}).get('account')
accounts = load_accounts()
if not acc_id or acc_id not in accounts:
return None
acc = accounts[acc_id]
reg = region_name or user_state[chat_id].get('region', 'ap-northeast-1')
return boto3.client(
service,
region_name=reg,
aws_access_key_id=acc['ak'],
aws_secret_access_key=acc['sk']
)

def send_key_file(chat_id, key_name, key_material, caption):
url = f"https://api.telegram.org/bot{TG_BOT_TOKEN}/sendDocument"
files = {'document': (f"{key_name}.pem", key_material)}
data = {'chat_id': chat_id, 'caption': caption, 'parse_mode': 'Markdown'}
try:
r = requests.post(url, data=data, files=files)
if not r.json().get('ok'):
bot.send_message(
chat_id, f"{caption}\n请保存:\n\n{key_material}\n",
parse_mode='Markdown'
)
except:
bot.send_message(
chat_id, f"{caption}\n请保存:\n\n{key_material}\n",
parse_mode='Markdown'
)

def process_add_ak(m):
if not is_allowed(m): return
cid = m.chat.id
if cid not in user_state: user_state[cid] = {}
user_state[cid]['temp_ak'] = m.text.strip()
msg = bot.send_message(
cid, "发送 AWS Secret Key (SK):",
parse_mode='Markdown'
)
bot.register_next_step_handler(msg, process_add_sk)

def process_add_sk(m):
if not is_allowed(m): return
cid = m.chat.id
user_state[cid]['temp_sk'] = m.text.strip()
msg = bot.send_message(
cid, "最后给账号起个别名:",
parse_mode='Markdown'
)
bot.register_next_step_handler(msg, process_add_alias)

def process_add_alias(m):
if not is_allowed(m): return
cid = m.chat.id
alias = m.text.strip()
ak = user_state[cid].get('temp_ak')
sk = user_state[cid].get('temp_sk')
if ak and sk:
accounts = load_accounts()
t = str(int(time.time() * 1000))
r = str(random.randint(100, 999))
acc_id = t + r
accounts[acc_id] = {'ak': ak, 'sk': sk, 'alias': alias}
save_accounts(accounts)
bot.send_message(
cid, f"✅ 账号 {alias} 绑定成功！请发送 /start",
parse_mode='Markdown'
)
else:
bot.send_message(cid, "❌ 绑定失败。")

def build_accounts_menu():
mk = InlineKeyboardMarkup()
accounts = load_accounts()
if accounts:
for k, v in accounts.items():
btn = InlineKeyboardButton(
f"👤 {v['alias']} (*{k[-4:]})",
callback_data=f"acc_{k}"
)
mk.add(btn)
btn_add = InlineKeyboardButton(
"➕ 绑定新 AWS 账号",
callback_data="add_account_start"
)
mk.add(btn_add)
return mk

def build_product_menu(cid):
mk = InlineKeyboardMarkup()
b1 = InlineKeyboardButton("⛵ Lightsail", callback_data="prod_ls")
b2 = InlineKeyboardButton("☁️ EC2", callback_data="prod_ec2")
mk.row(b1, b2)
b3 = InlineKeyboardButton("🔙 返回", callback_data="back_accounts")
b4 = InlineKeyboardButton("🗑️ 解绑", callback_data="unbind_current_acc")
mk.row(b3, b4)
return mk

def build_regions_menu(cid):
mk = InlineKeyboardMarkup()
try:
prod = user_state[cid].get('product', 'ls')
c = get_boto_client('lightsail' if prod == 'ls' else 'ec2', cid)
if prod == 'ls':
regions = c.get_regions()['regions']
btns = [
InlineKeyboardButton(
f"📍 {r['displayName']}",
callback_data=f"r_{r['name']}"
) for r in regions
]
else:
regions = c.describe_regions()['Regions']
btns = [
InlineKeyboardButton(
f"📍 {r['RegionName']}",
callback_data=f"r_{r['RegionName']}"
) for r in regions
]
for i in range(0, len(btns), 2):
mk.row(*btns[i:i+2])
except:
pass
b_back = InlineKeyboardButton("🔙 返回", callback_data="back_products")
mk.add(b_back)
return mk

def build_instances_menu(cid, instances):
mk = InlineKeyboardMarkup()
prod = user_state[cid]['product']
for i in instances:
if prod == 'ls':
icon = "🟢" if i['state']['name'] == 'running' else "🛑"
ip = i.get('publicIpAddress', '无IP')
inst_id = i['name']
name = i['name']
else:
icon = "🟢" if i['State']['Name'] == 'running' else "🛑"
ip = i.get('PublicIpAddress', '无IP')
inst_id = i['InstanceId']
tags = i.get('Tags', [])
name = next((t['Value'] for t in tags if t['Key'] == 'Name'), inst_id)
btn = InlineKeyboardButton(
f"{icon} {name[:20]} ({ip})",
callback_data=f"i_{inst_id}"
)
mk.add(btn)
b1 = InlineKeyboardButton(
f"➕ 创建新 {prod.upper()}",
callback_data="action_create"
)
b2 = InlineKeyboardButton("🔙 返回区域", callback_data="back_regions")
mk.add(b1)
mk.add(b2)
return mk

def build_action_menu(cid):
mk = InlineKeyboardMarkup()
b1 = InlineKeyboardButton("🟢 开机", callback_data="a_start")
b2 = InlineKeyboardButton("🛑 关机", callback_data="a_stop")
b3 = InlineKeyboardButton("🔄 重启", callback_data="a_reboot")
mk.row(b1, b2, b3)
b4 = InlineKeyboardButton("🛡️ 防火墙", callback_data="a_fw_panel")
b5 = InlineKeyboardButton("🔄 更换 IP / IPv6", callback_data="a_change_ip")
mk.row(b4, b5)
b6 = InlineKeyboardButton("📊 刷新", callback_data="a_status")
b7 = InlineKeyboardButton("🗑️ 删除", callback_data="a_delete")
mk.row(b6, b7)
b8 = InlineKeyboardButton("🔙 返回", callback_data="back_instances")
mk.row(b8)
return mk

def build_fw_menu(cid):
mk = InlineKeyboardMarkup()
sel = user_state[cid].get('fw_ports', ['ICMP'])
btns = []
for port, desc in PORTS_DICT.items():
if port in sel:
txt = f"✅ {port} ({desc})"
else:
txt = f"⬜️ {port} ({desc})"
btns.append(InlineKeyboardButton(txt, callback_data=f"fw_toggle_{port}"))
for i in range(0, len(btns), 2):
mk.row(*btns[i:i+2])
b1 = InlineKeyboardButton("💾 应用双栈规则", callback_data="fw_apply")
b2 = InlineKeyboardButton("🔙 取消", callback_data="a_back_inst_action")
mk.add(b1)
mk.add(b2)
return mk

def build_az_menu(cid):
mk = InlineKeyboardMarkup()
prod = user_state[cid]['product']
reg = user_state[cid]['region']
try:
if prod == 'ls':
c = get_boto_client('lightsail', cid, reg)
res = c.get_regions(includeAvailabilityZones=True)['regions']
azs = next(r['availabilityZones'] for r in res if r['name'] == reg)
for az in azs:
if az['state'] == 'available':
b = InlineKeyboardButton(
f"📍 {az['zoneName']}",
callback_data=f"az_{az['zoneName']}"
)
mk.add(b)
else:
c = get_boto_client('ec2', cid, reg)
azs = c.describe_availability_zones()['AvailabilityZones']
for az in azs:
if az['State'] == 'available':
b = InlineKeyboardButton(
f"📍 {az['ZoneName']}",
callback_data=f"az_{az['ZoneName']}"
)
mk.add(b)
except:
pass
b_cancel = InlineKeyboardButton("🔙 取消", callback_data="back_instances")
mk.add(b_cancel)
return mk

def build_ec2_os_menu():
mk = InlineKeyboardMarkup()
b1 = InlineKeyboardButton("🐧 Ubuntu 24.04", callback_data="os_ubuntu24")
b2 = InlineKeyboardButton("🐧 Debian 12", callback_data="os_debian12")
b3 = InlineKeyboardButton("🐧 AL 2023", callback_data="os_al2023")
b4 = InlineKeyboardButton("🔙 取消", callback_data="back_instances")
mk.row(b1)
mk.row(b2)
mk.row(b3)
mk.add(b4)
return mk

def build_ec2_type_menu():
mk = InlineKeyboardMarkup()
b1 = InlineKeyboardButton("💻 t2.micro", callback_data="bd_t2.micro")
b2 = InlineKeyboardButton("💻 t3.micro [免]", callback_data="bd_t3.micro")
b3 = InlineKeyboardButton("🚀 t4g.nano", callback_data="bd_t4g.nano")
b4 = InlineKeyboardButton("🚀 t4g.micro", callback_data="bd_t4g.micro")
b5 = InlineKeyboardButton("🔙 取消", callback_data="back_instances")
mk.add(b1)
mk.add(b2)
mk.add(b3)
mk.add(b4)
mk.add(b5)
return mk

def update_ec2_sg(client, sg_id, port_infos):
try:
desc = client.describe_security_groups(GroupIds=[sg_id])
sg = desc['SecurityGroups'][0]
if sg.get('IpPermissions'):
client.revoke_security_group_ingress(
GroupId=sg_id,
IpPermissions=sg['IpPermissions']
)
ip_perms = []
for p in port_infos:
rule = {
'IpProtocol': p['protocol'],
'FromPort': p['fromPort'],
'ToPort': p['toPort'],
'IpRanges': [{'CidrIp': '0.0.0.0/0'}],
'Ipv6Ranges': [{'CidrIpv6': '::/0'}]
}
if p['protocol'] == 'icmp':
rule['FromPort'] = -1
rule['ToPort'] = -1
ip_perms.append(rule)
if ip_perms:
client.authorize_security_group_ingress(
GroupId=sg_id,
IpPermissions=ip_perms
)
except:
pass

@bot.message_handler(commands=['start', 'menu'])
def send_welcome(m):
if not is_allowed(m): return
cid = m.chat.id
if cid not in user_state:
user_state[cid] = {}
mk = build_accounts_menu()
bot.send_message(
cid, "🏢 AWS 终极双擎管家",
reply_markup=mk, parse_mode='Markdown'
)

@bot.callback_query_handler(func=lambda call: True)
def handle_callback(call):
if not is_allowed(call.message): return
cid = call.message.chat.id
data = call.data
mid = call.message.message_id
if cid not in user_state:
user_state[cid] = {}

try:
    if data == "add_account_start":
        msg = bot.send_message(
            cid, "🔑 请发送 **AK**:",
            parse_mode='Markdown'
        )
        bot.register_next_step_handler(msg, process_add_ak)
        return
        
    if data == "unbind_current_acc":
        acc = user_state[cid].get('account')
        db = load_accounts()
        if acc and acc in db:
            del db[acc]
            save_accounts(db)
        mk = build_accounts_menu()
        bot.edit_message_text(
            "🏢 **账号管理**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data == "back_accounts": 
        mk = build_accounts_menu()
        bot.edit_message_text(
            "🏢 **账号管理**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("acc_"):
        user_state[cid]['account'] = data[4:]
        mk = build_product_menu(cid)
        bot.edit_message_text(
            "⚙️ **请选择产品线：**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data == "back_products":
        mk = build_product_menu(cid)
        bot.edit_message_text(
            "⚙️ **请选择产品线：**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("prod_"):
        p = data.split("_")[1]
        user_state[cid]['product'] = p
        mk = build_regions_menu(cid)
        txt = f"📦 产品: {p}\n🌐 **请选择区域：**"
        bot.edit_message_text(
            txt, cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return

    prod = user_state[cid].get('product', 'ls')
    c = get_boto_client('lightsail' if prod == 'ls' else 'ec2', cid)
    if not c:
        bot.answer_callback_query(call.id, "请先选择账号！", show_alert=True)
        return

    if data == "back_regions": 
        mk = build_regions_menu(cid)
        bot.edit_message_text(
            "🌐 **请选择区域：**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data == "back_instances":
        if prod == 'ls':
            insts = c.get_instances().get('instances', [])
        else:
            desc = c.describe_instances()
            rs = desc['Reservations']
            insts = [i for r in rs for i in r['Instances'] if i['State']['Name'] != 'terminated']
        reg = user_state[cid].get('region')
        mk = build_instances_menu(cid, insts)
        bot.edit_message_text(
            f"📍 区域 `{reg}` 的实例：", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("r_"):
        reg = data.split("_")[1]
        user_state[cid]['region'] = reg
        c = get_boto_client('lightsail' if prod == 'ls' else 'ec2', cid)
        if prod == 'ls':
            insts = c.get_instances().get('instances', [])
        else:
            desc = c.describe_instances()
            rs = desc['Reservations']
            insts = [i for r in rs for i in r['Instances'] if i['State']['Name'] != 'terminated']
        mk = build_instances_menu(cid, insts)
        bot.edit_message_text(
            f"📍 当前区域: `{reg}`", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("i_"):
        user_state[cid]['instance'] = data[2:]
        mk = build_action_menu(cid)
        bot.edit_message_text(
            f"⚙️ 实例: `{data[2:]}`", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data == "a_back_inst_action":
        iid = user_state[cid].get('instance')
        mk = build_action_menu(cid)
        bot.edit_message_text(
            f"⚙️ 实例: `{iid}`", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return

    if data.startswith("a_"):
        act = data[2:]
        iid = user_state[cid].get('instance')
        
        if act == "start": 
            if prod == 'ls': c.start_instance(instanceName=iid)
            else: c.start_instances(InstanceIds=[iid])
            bot.answer_callback_query(call.id, "✅ 已开机")
            
        elif act == "stop": 
            if prod == 'ls': c.stop_instance(instanceName=iid)
            else: c.stop_instances(InstanceIds=[iid])
            bot.answer_callback_query(call.id, "🛑 已关机")
            
        elif act == "reboot": 
            if prod == 'ls': c.reboot_instance(instanceName=iid)
            else: c.reboot_instances(InstanceIds=[iid])
            bot.answer_callback_query(call.id, "🔄 已重启")
            
        elif act == "delete": 
            if prod == 'ls': c.delete_instance(instanceName=iid)
            else: c.terminate_instances(InstanceIds=[iid])
            bot.send_message(cid, f"🗑️ 实例 `{iid}` 已销毁")
            
        elif act == "status":
            if prod == 'ls':
                r = c.get_instance(instanceName=iid)['instance']
                ip = r.get('publicIpAddress', '无')
                state = r['state']['name']
                os_user = 'root'
                ipv6 = '无'
                v6_list = r.get('ipv6Addresses')
                if v6_list:
                    ipv6 = v6_list[0]
            else:
                desc = c.describe_instances(InstanceIds=[iid])
                r = desc['Reservations'][0]['Instances'][0]
                ip = r.get('PublicIpAddress', '无')
                state = r['State']['Name']
                os_user = 'Debian(admin) | Ubuntu(ubuntu) | AL(ec2-user)'
                ipv6 = '无'
                enis = r.get('NetworkInterfaces', [])
                if enis:
                    v6_addrs = enis[0].get('Ipv6Addresses')
                    if v6_addrs:
                        ipv6 = v6_addrs[0]['Ipv6Address']
            msg_txt = f"📊 状态: `{state}`\n🌐 IPv4: `{ip}`\n🌍 IPv6: `{ipv6}`\n👤 用户: `{os_user}`"
            bot.send_message(cid, msg_txt)
            
        elif act == "change_ip":
            mk = InlineKeyboardMarkup()
            b1 = InlineKeyboardButton("🔄 换 IPv4", callback_data="change_ip_v4")
            b2 = InlineKeyboardButton("🔄 换 IPv6", callback_data="change_ip_v6")
            b3 = InlineKeyboardButton("🔙 返回", callback_data="a_back_inst_action")
            mk.row(b1, b2)
            mk.add(b3)
            bot.edit_message_text("请选择网络协议：", cid, mid, reply_markup=mk)
            
        elif act == "fw_panel":
            msg_txt = f"🛡️ `{iid}` 防火墙策略：\n"
            if prod == 'ls':
                ports = c.get_instance_port_states(instanceName=iid)
                port_list = ports.get('portStates', [])
                for p in port_list:
                    if p.get('state') == 'open':
                        pro = p.get('protocol').upper()
                        p_num = p.get('fromPort')
                        msg_txt += f"🔹 `{pro}` | 端口 `{p_num}`\n"
            else:
                desc = c.describe_instances(InstanceIds=[iid])
                r = desc['Reservations'][0]['Instances'][0]
                sg_id = r['SecurityGroups'][0]['GroupId']
                user_state[cid]['ec2_sg_id'] = sg_id
                sgs = c.describe_security_groups(GroupIds=[sg_id])
                sg_info = sgs['SecurityGroups'][0]
                for p in sg_info.get('IpPermissions', []):
                    pro = str(p.get('IpProtocol')).upper()
                    p_num = p.get('FromPort', 'All')
                    msg_txt += f"🔹 `{pro}` | `{p_num}`\n"
            mk = InlineKeyboardMarkup()
            b1 = InlineKeyboardButton("🔓 全开双栈", callback_data="fw_all")
            b2 = InlineKeyboardButton("🛡️ 防Ping", callback_data="fw_def")
            b3 = InlineKeyboardButton("🛠️ 自定义", callback_data="fw_custom")
            b4 = InlineKeyboardButton("🔙 返回", callback_data="a_back_inst_action")
            mk.row(b1, b2)
            mk.row(b3)
            mk.row(b4)
            bot.edit_message_text(
                msg_txt, cid, mid,
                reply_markup=mk, parse_mode='Markdown'
            )
        return

    if data == "change_ip_v4":
        bot.answer_callback_query(call.id, "换 IPv4 中...")
        iid = user_state[cid].get('instance')
        prod = user_state[cid].get('product', 'ls')
        c = get_boto_client('lightsail' if prod == 'ls' else 'ec2', cid)
        try:
            if prod == 'ls':
                s_ips = c.get_static_ips().get('staticIps', [])
                att = None
                for s in s_ips:
                    if s.get('attachedTo') == iid:
                        att = s['name']
                        break
                if att:
                    c.detach_static_ip(staticIpName=att)
                    c.release_static_ip(staticIpName=att)
                    time.sleep(1)
                ns = f"IP-{int(time.time())}"
                c.allocate_static_ip(staticIpName=ns)
                c.attach_static_ip(staticIpName=ns, instanceName=iid)
            else:
                addrs = c.describe_addresses()['Addresses']
                att = None
                for a in addrs:
                    if a.get('InstanceId') == iid:
                        att = a
                        break
                if att:
                    c.disassociate_address(AssociationId=att['AssociationId'])
                    c.release_address(AllocationId=att['AllocationId'])
                    time.sleep(1)
                al = c.allocate_address(Domain='vpc')
                c.associate_address(
                    AllocationId=al['AllocationId'],
                    InstanceId=iid
                )
            bot.send_message(cid, f"✅ `{iid}` IPv4 更换成功！")
        except Exception as e:
            bot.send_message(cid, f"❌ IPv4 失败: {e}")
        return
        
    if data == "change_ip_v6":
        bot.answer_callback_query(call.id, "处理 IPv6 中...")
        iid = user_state[cid].get('instance')
        prod = user_state[cid].get('product', 'ls')
        c = get_boto_client('lightsail' if prod == 'ls' else 'ec2', cid)
        try:
            if prod == 'ls':
                bot.send_message(cid, "⚠️ LS 不支持单独重置 IPv6。")
            else:
                desc = c.describe_instances(InstanceIds=[iid])
                r = desc['Reservations'][0]['Instances'][0]
                enis = r.get('NetworkInterfaces', [])
                if not enis:
                    raise Exception("未发现网卡")
                eni_id = enis[0]['NetworkInterfaceId']
                subnet_id = enis[0]['SubnetId']
                vpc_id = enis[0]['VpcId']
                v6_addrs = enis[0].get('Ipv6Addresses', [])
                
                if v6_addrs:
                    ips = [x['Ipv6Address'] for x in v6_addrs]
                    c.unassign_ipv6_addresses(
                        NetworkInterfaceId=eni_id,
                        Ipv6Addresses=ips
                    )
                    time.sleep(2)
                    
                try:
                    c.assign_ipv6_addresses(
                        NetworkInterfaceId=eni_id,
                        Ipv6AddressCount=1
                    )
                    bot.send_message(cid, f"✅ `{iid}` IPv6 成功！")
                except Exception as err:
                    if "Subnet does not contain" in str(err):
                        bot.send_message(
                            cid, "⏳ 正在自动向 AWS 申请 IPv6 资源池..."
                        )
                        v_desc = c.describe_vpcs(VpcIds=[vpc_id])
                        vpc_info = v_desc['Vpcs'][0]
                        assocs = vpc_info.get('Ipv6CidrBlockAssociationSet')
                        if not assocs:
                            c.associate_vpc_cidr_block(
                                VpcId=vpc_id,
                                AmazonProvidedIpv6CidrBlock=True
                            )
                            time.sleep(3)
                            v_desc = c.describe_vpcs(VpcIds=[vpc_id])
                            vpc_info = v_desc['Vpcs'][0]
                        
                        assocs = vpc_info.get('Ipv6CidrBlockAssociationSet', [])
                        v6_cidr = ""
                        for a in assocs:
                            st = a['Ipv6CidrBlockState']['State']
                            if st in ['associated', 'associating']:
                                v6_cidr = a['Ipv6CidrBlock']
                                break
                        sub_cidr = v6_cidr.replace('/56', '/64')
                        c.associate_subnet_cidr_block(
                            SubnetId=subnet_id,
                            Ipv6CidrBlock=sub_cidr
                        )
                        time.sleep(3)
                        c.assign_ipv6_addresses(
                            NetworkInterfaceId=eni_id,
                            Ipv6AddressCount=1
                        )
                        bot.send_message(cid, f"✅ `{iid}` IPv6 资源池分配完成！")
                    else:
                        bot.send_message(cid, f"❌ IPv6 失败: {err}")
        except Exception as e:
            bot.send_message(cid, f"❌ 异常: {e}")
        return

    if data == "fw_custom":
        user_state[cid]['fw_ports'] = ['ICMP'] 
        mk = build_fw_menu(cid)
        bot.edit_message_text("🛠 菜单防火墙", cid, mid, reply_markup=mk)
        return
        
    if data == "fw_all": 
        iid = user_state[cid].get('instance')
        if prod == 'ls':
            rules = [
                {'fromPort': 0, 'toPort': 65535, 'protocol': 'tcp'},
                {'fromPort': 0, 'toPort': 65535, 'protocol': 'udp'},
                {'fromPort': -1, 'toPort': -1, 'protocol': 'icmp'}
            ]
            c.put_instance_public_ports(portInfos=rules, instanceName=iid)
        else:
            rules = [
                {'fromPort': 0, 'toPort': 65535, 'protocol': 'tcp'},
                {'fromPort': 0, 'toPort': 65535, 'protocol': 'udp'},
                {'protocol': 'icmp'}
            ]
            update_ec2_sg(c, user_state[cid]['ec2_sg_id'], rules)
        bot.answer_callback_query(call.id, "✅ 已全开双栈端口")
        return
        
    if data == "fw_def": 
        iid = user_state[cid].get('instance')
        if prod == 'ls':
            rules = [
                {'fromPort': 22, 'toPort': 22, 'protocol': 'tcp'},
                {'fromPort': 80, 'toPort': 80, 'protocol': 'tcp'},
                {'fromPort': 443, 'toPort': 443, 'protocol': 'tcp'}
            ]
            c.put_instance_public_ports(portInfos=rules, instanceName=iid)
        else:
            rules = [
                {'fromPort': 22, 'toPort': 22, 'protocol': 'tcp'},
                {'fromPort': 80, 'toPort': 80, 'protocol': 'tcp'},
                {'fromPort': 443, 'toPort': 443, 'protocol': 'tcp'}
            ]
            update_ec2_sg(c, user_state[cid]['ec2_sg_id'], rules)
        bot.answer_callback_query(call.id, "✅ 恢复双栈默认")
        return
        
    if data.startswith("fw_toggle_"):
        port = data.split("_", 2)[2]
        if port in user_state[cid]['fw_ports']:
            user_state[cid]['fw_ports'].remove(port)
        else:
            user_state[cid]['fw_ports'].append(port)
        mk = build_fw_menu(cid)
        bot.edit_message_reply_markup(cid, mid, reply_markup=mk)
        return
        
    if data == "fw_apply":
        bot.answer_callback_query(call.id, "下发双栈规则中...")
        pi = [{'fromPort': 22, 'toPort': 22, 'protocol': 'tcp'}]
        for p in user_state[cid].get('fw_ports', []):
            if p == 'ICMP':
                pi.append({'fromPort': -1, 'toPort': -1, 'protocol': 'icmp'})
            else:
                pi.append({'fromPort': int(p), 'toPort': int(p), 'protocol': 'tcp'})
        if prod == 'ls':
            c.put_instance_public_ports(
                portInfos=pi,
                instanceName=user_state[cid]['instance']
            )
        else:
            update_ec2_sg(c, user_state[cid]['ec2_sg_id'], pi)
        mk = build_action_menu(cid)
        bot.edit_message_text("✅ 防火墙生效！", cid, mid, reply_markup=mk)
        return

    if data == "action_create":
        mk = build_az_menu(cid)
        bot.edit_message_text(
            "**第一步：选可用区**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("az_"):
        user_state[cid]['target_zone'] = data[3:]
        if user_state[cid]['product'] == 'ls':
            res = c.get_blueprints(includeInactive=False)
            mk = InlineKeyboardMarkup()
            bps = res.get('blueprints', [])
            btns = []
            for bp in bps:
                if bp.get('type') == 'os' and bp.get('platform') == 'LINUX_UNIX':
                    b = InlineKeyboardButton(
                        f"🐧 {bp['name']}",
                        callback_data=f"os_{bp['blueprintId']}"
                    )
                    btns.append(b)
            for i in range(0, len(btns), 2):
                mk.row(*btns[i:i+2])
            mk.add(InlineKeyboardButton("🔙 取消", callback_data="back_instances"))
        else:
            mk = build_ec2_os_menu()
        bot.edit_message_text(
            "**第二步：选系统**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("os_"):
        user_state[cid]['target_os'] = data[3:]
        if user_state[cid]['product'] == 'ls':
            res = c.get_bundles(includeInactive=False)
            bds = res.get('bundles', [])
            lbs = []
            for bd in bds:
                if 'LINUX_UNIX' in bd.get('supportedPlatforms', []):
                    lbs.append(bd)
            lbs = sorted(lbs, key=lambda x: x.get('price', 0))
            mk = InlineKeyboardMarkup()
            for bd in lbs[:8]:
                it = "[v6]" if "ipv6" in bd['bundleId'].lower() else "[v4]"
                fl = " [免]" if bd.get('price', 100) <= 7.0 else ""
                txt = f"💰 ${bd['price']} {it}{fl} ({bd['ramSizeInGb']}G)"
                b = InlineKeyboardButton(txt, callback_data=f"bd_{bd['bundleId']}")
                mk.add(b)
            mk.add(InlineKeyboardButton("🔙 取消", callback_data="back_instances"))
        else:
            mk = build_ec2_type_menu()
        bot.edit_message_text(
            "**第三步：选配置**", cid, mid,
            reply_markup=mk, parse_mode='Markdown'
        )
        return
        
    if data.startswith("bd_"):
        bot.edit_message_text("⏳ 正在请求双栈开机环境...", cid, mid)
        reg = user_state[cid]['region']
        tz = user_state[cid]['target_zone']
        to = user_state[cid]['target_os']
        bid = data[3:]
        cc = REGION_CODES.get(reg, 'XX')
        t_str = datetime.datetime.now().strftime('%Y%m%d%H%M%S')
        nm = f"{cc}{t_str}{get_seq():02d}"
        
        if user_state[cid]['product'] == 'ls':
            kn = f"TG-Key-LS-{reg}-v2"
            try:
                c.get_key_pair(keyPairName=kn)
            except:
                nk = c.create_key_pair(keyPairName=kn)
                send_key_file(cid, kn, nk['privateKeyBase64'], "🚨 **保存私钥**")
            c.create_instances(
                instanceNames=[nm],
                availabilityZone=tz,
                blueprintId=to,
                bundleId=bid,
                keyPairName=kn,
                ipAddressType='dualstack'
            )
            bot.send_message(
                cid, f"✅ **开机成功！**\n名称: `{nm}`\n区: `{tz}`",
                parse_mode='Markdown'
            )
        else:
            ec2 = get_boto_client('ec2', cid)
            ssm = get_boto_client('ssm', cid)
            arch = 'arm64' if 'g.' in bid else 'amd64'
            
            b1 = '/aws/service/canonical/ubuntu/server/24.04/1.0/current'
            b2 = '/aws/service/debian/release/12/latest'
            b3 = '/aws/service/ami-amazon-linux-latest'
            
            paths = {
                'ubuntu24': {
                    'amd64': f'{b1}/amd64/hvm/ebs-gp3/ami-id',
                    'arm64': f'{b1}/arm64/hvm/ebs-gp3/ami-id'
                },
                'debian12': {
                    'amd64': f'{b2}/amd64',
                    'arm64': f'{b2}/arm64'
                },
                'al2023': {
                    'amd64': f'{b3}/al2023-ami-kernel-default-x86_64',
                    'arm64': f'{b3}/al2023-ami-kernel-default-arm64'
                }
            }
            
            p_name = paths.get(to, paths['ubuntu24'])[arch]
            ami = ssm.get_parameter(Name=p_name)['Parameter']['Value']
            
            fils = [
                {'Name': 'availability-zone', 'Values': [tz]},
                {'Name': 'default-for-az', 'Values': ['true']}
            ]
            subs = ec2.describe_subnets(Filters=fils)
            if not subs['Subnets']:
                raise Exception("未发现可用子网，请检查区域 VPC。")
                
            sid = subs['Subnets'][0]['SubnetId']
            vid = subs['Subnets'][0]['VpcId']
            sgn = f"TG-Bot-SG-{vid}"
            
            try:
                s_fils = [
                    {'Name': 'group-name', 'Values': [sgn]},
                    {'Name': 'vpc-id', 'Values': [vid]}
                ]
                sgs = ec2.describe_security_groups(Filters=s_fils)
                if sgs['SecurityGroups']:
                    sgid = sgs['SecurityGroups'][0]['GroupId']
                else:
                    res_sg = ec2.create_security_group(
                        GroupName=sgn,
                        Description='Created by TG Bot',
                        VpcId=vid
                    )
                    sgid = res_sg['GroupId']
                    rule = [{
                        'IpProtocol': 'tcp',
                        'FromPort': 22,
                        'ToPort': 22,
                        'IpRanges': [{'CidrIp': '0.0.0.0/0'}],
                        'Ipv6Ranges': [{'CidrIpv6': '::/0'}]
                    }]
                    ec2.authorize_security_group_ingress(
                        GroupId=sgid,
                        IpPermissions=rule
                    )
            except:
                raise Exception("安全组操作失败")
                
            kn = f"TG-Key-EC2-{reg}-v2"
            try:
                ec2.describe_key_pairs(KeyNames=[kn])
            except:
                kp = ec2.create_key_pair(KeyName=kn)
                send_key_file(cid, kn, kp['KeyMaterial'], "🚨 **保存私钥**")
            
            try:
                run_args = {
                    'ImageId': ami, 'InstanceType': bid,
                    'MinCount': 1, 'MaxCount': 1, 'KeyName': kn,
                    'NetworkInterfaces': [{
                        'DeviceIndex': 0, 'SubnetId': sid,
                        'Groups': [sgid],
                        'AssociatePublicIpAddress': True,
                        'Ipv6AddressCount': 1
                    }],
                    'TagSpecifications': [{
                        'ResourceType': 'instance',
                        'Tags': [{'Key': 'Name', 'Value': nm}]
                    }]
                }
                ec2.run_instances(**run_args)
            except Exception as run_err:
                bot.edit_message_text(f"⏳ 向 AWS 申请 IPv6...", cid, mid)
                try:
                    v_desc = ec2.describe_vpcs(VpcIds=[vid])
                    vpc_info = v_desc['Vpcs'][0]
                    if not vpc_info.get('Ipv6CidrBlockAssociationSet'):
                        ec2.associate_vpc_cidr_block(
                            VpcId=vid,
                            AmazonProvidedIpv6CidrBlock=True
                        )
                        time.sleep(3)
                        v_desc = ec2.describe_vpcs(VpcIds=[vid])
                        vpc_info = v_desc['Vpcs'][0]
                    
                    assocs = vpc_info.get('Ipv6CidrBlockAssociationSet', [])
                    v6_cidr = ""
                    for a in assocs:
                        st = a['Ipv6CidrBlockState']['State']
                        if st in ['associated', 'associating']:
                            v6_cidr = a['Ipv6CidrBlock']
                            break
                    sub_cidr = v6_cidr.replace('/56', '/64')
                    ec2.associate_subnet_cidr_block(
                        SubnetId=sid,
                        Ipv6CidrBlock=sub_cidr
                    )
                    time.sleep(2)
                    run_args['NetworkInterfaces'][0]['Ipv6AddressCount'] = 1
                    ec2.run_instances(**run_args)
                except:
                    bot.send_message(cid, "⚠️ IPv6 失败，降级纯 IPv4。")
                    run_args['NetworkInterfaces'][0].pop('Ipv6AddressCount', None)
                    ec2.run_instances(**run_args)
            bot.send_message(
                cid, f"✅ **开机成功！**\n名称: `{nm}`\n区: `{tz}`",
                parse_mode='Markdown'
            )
        return
        
except Exception as ex:
    bot.send_message(cid, f"❌ 错误：\n`{str(ex)}`")


if name == 'main':
while True:
try:
bot.polling(none_stop=True, timeout=60)
except Exception as e:
time.sleep(5)
EOF_PYTHON

echo -e "\n======================================================="
echo " 🚀 [4/4] 正在配置系统守护进程并启动服务..."
echo "======================================================="
cat > "$SERVICE_FILE" <<EOF


[Unit]
Description=AWS Lightsail & EC2 Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment="TG_BOT_TOKEN=$INPUT_TOKEN"
Environment="TG_USER_ID=$INPUT_ID"
ExecStart=/usr/bin/python3 $BOT_SCRIPT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lightsail-bot > /dev/null 2>&1
systemctl restart lightsail-bot
echo "🎉 部署完成！当前进程状态："
systemctl status lightsail-bot --no-pager | head -n 3


}

activate_regions() {
echo -e "\n======================================================="
echo " 🌐 准备探测并激活 AWS 隐藏区域"
echo "======================================================="

if [ ! -f "$ACCOUNTS_FILE" ]; then
    echo "❌ 错误: 未检测到账号配置文件！请先部署机器人并绑定账号。"
    return
fi

if ! command -v aws &> /dev/null; then
    echo "⏳ 正在拉取官方 AWS 独立引擎..."
    if ! command -v unzip &> /dev/null; then
        yum install -y unzip curl >/dev/null 2>&1 || apt-get install -y unzip curl >/dev/null 2>&1
    fi
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
    else
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    fi
    unzip -q awscliv2.zip
    ./aws/install >/dev/null 2>&1
    rm -rf aws awscliv2.zip
fi

cat > /tmp/select_aws_account.py << 'EOF_PY'


import json, sys
try:
with open('/root/lightsail_accounts.json', 'r') as f:
accs = json.load(f)
except:
sys.exit("ERROR: 读取配置失败")
if not accs:
sys.exit("ERROR: 未找到账号数据")

lst = list(accs.items())
print("\n📦 已读取本地配置，请选择你要操作的 AWS 账号：")
for i, (k, v) in enumerate(lst):
print(f"[{i}] 别名: {v['alias']} (AK尾号: {v['ak'][-4:]})")

try:
c = input("\n👉 请输入对应的序号: ")
sel = lst[int(c)][1]
with open('/tmp/aws_creds.txt', 'w') as f:
f.write(f"{sel['ak']}\n{sel['sk']}\n")
except Exception as e:
sys.exit(f"ERROR: 序号输入有误 {e}")
EOF_PY

python3 /tmp/select_aws_account.py
if [ $? -ne 0 ]; then
    rm -f /tmp/select_aws_account.py
    return
fi

AK=$(sed -n '1p' /tmp/aws_creds.txt)
SK=$(sed -n '2p' /tmp/aws_creds.txt)
rm -f /tmp/aws_creds.txt /tmp/select_aws_account.py

export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
export AWS_DEFAULT_REGION="us-east-1"

echo -e "\n⏳ 正在探测全球未激活区域..."
REGIONS=$(aws ec2 describe-regions --all-regions --query "Regions[?OptInStatus=='not-opted-in'].RegionName" --output text 2>/dev/null)

if [ -z "$REGIONS" ]; then
    echo "✅ 该账号在全球的所有区域均已可用！"
    return
fi

echo -e "\n🔍 发现以下隐藏区域尚未激活："
REG_ARRAY=($REGIONS)
for i in "${!REG_ARRAY[@]}"; do
    echo "[$i] ${REG_ARRAY[$i]}"
done

echo ""
read -p "👉 请输入你要激活的区域序号: " REG_CHOICE
TARGET_REG="${REG_ARRAY[$REG_CHOICE]}"
if [ -z "$TARGET_REG" ]; then
    echo "❌ 无效的序号！"
    return
fi

echo -e "\n⏳ 正在激活 [$TARGET_REG]..."
aws account enable-region --region-name "$TARGET_REG"
if [ $? -eq 0 ]; then
    echo -e "\n✅ 激活指令下发成功！后台配置约需 5~15 分钟。"
else
    echo -e "\n❌ 激活失败！通常因为 IAM 用户缺乏 account:EnableRegion 权限。"
fi


}

force_restart_bot() {
echo -e "\n======================================================="
echo " 🧰 物理急救：强制终止并重启机器人进程..."
echo "======================================================="
pkill -f lightsail_master_bot.py
systemctl restart lightsail-bot && systemctl status lightsail-bot --no-pager
echo "✅ 操作完毕！服务已重新拉起。"
}

clear
echo "="
echo "   🛡️ AWS 终极双擎双栈云管控制台 v3.6 (GitHub开源版)"
echo "="
while true; do
echo ""
echo "请选择操作："
echo " [1] 部署/重置 机器人主程序 (保留本地数据)"
echo " [2] 扫描并激活 AWS 全球隐藏区域"
echo " [3] 退出工具箱"
echo " [4] 物理急救 (修复机器人卡死/无响应)"
echo ""
read -p "👉 你的选择 (1/2/3/4): " MAIN_CHOICE

case $MAIN_CHOICE in
    1) deploy_bot ;;
    2) activate_regions ;;
    3) exit 0 ;;
    4) force_restart_bot ;;
    *) echo "❌ 无效输入" ;;
esac


done
