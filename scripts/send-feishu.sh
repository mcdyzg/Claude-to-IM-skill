#!/usr/bin/env bash
# 向指定飞书用户发送消息（通过 open_id）
set -euo pipefail

CTI_HOME="${CTI_HOME:-$HOME/.claude-to-im}"
CONFIG_FILE="$CTI_HOME/config.env"

# ── 参数校验 ──

usage() {
  echo "Usage: $0 <open_id> <message>"
  echo ""
  echo "  open_id   飞书用户的 open_id"
  echo "  message   要发送的消息内容（支持纯文本）"
  exit 1
}

if [ $# -lt 2 ]; then
  usage
fi

OPEN_ID="$1"
shift
MESSAGE="$*"

if [ -z "$OPEN_ID" ] || [ -z "$MESSAGE" ]; then
  usage
fi

# ── 读取配置 ──

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 配置文件不存在: $CONFIG_FILE"
  echo "   请先运行 /claude-to-im setup 完成配置"
  exit 1
fi

# 从 config.env 中提取飞书凭据
get_config() {
  local key="$1"
  local val
  val=$(grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
  # 去除可能的引号
  val="${val#\"}"
  val="${val%\"}"
  val="${val#\'}"
  val="${val%\'}"
  echo "$val"
}

APP_ID=$(get_config "CTI_FEISHU_APP_ID")
APP_SECRET=$(get_config "CTI_FEISHU_APP_SECRET")
DOMAIN=$(get_config "CTI_FEISHU_DOMAIN")

# 默认域名
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "feishu" ]; then
  DOMAIN="https://open.feishu.cn"
elif [ "$DOMAIN" = "lark" ]; then
  DOMAIN="https://open.larksuite.com"
fi

if [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ]; then
  echo "❌ 飞书凭据未配置（CTI_FEISHU_APP_ID / CTI_FEISHU_APP_SECRET）"
  echo "   请先运行 /claude-to-im setup 或 /claude-to-im reconfigure 配置飞书"
  exit 1
fi

# ── 获取 tenant_access_token ──

TOKEN_RESP=$(curl -s -X POST "${DOMAIN}/open-apis/auth/v3/tenant_access_token/internal" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\":\"${APP_ID}\",\"app_secret\":\"${APP_SECRET}\"}")

TOKEN_CODE=$(echo "$TOKEN_RESP" | grep -o '"code":[0-9]*' | head -1 | cut -d':' -f2 || echo "")
TENANT_TOKEN=$(echo "$TOKEN_RESP" | grep -o '"tenant_access_token":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")

if [ "$TOKEN_CODE" != "0" ] || [ -z "$TENANT_TOKEN" ]; then
  echo "❌ 获取 tenant_access_token 失败"
  echo "   响应: $TOKEN_RESP"
  exit 1
fi

# ── 发送消息 ──

# 转义 JSON 特殊字符
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

ESCAPED_MSG=$(escape_json "$MESSAGE")

SEND_RESP=$(curl -s -X POST "${DOMAIN}/open-apis/im/v1/messages?receive_id_type=open_id" \
  -H "Authorization: Bearer ${TENANT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"receive_id\":\"${OPEN_ID}\",\"msg_type\":\"text\",\"content\":\"{\\\"text\\\":\\\"${ESCAPED_MSG}\\\"}\"}")

SEND_CODE=$(echo "$SEND_RESP" | grep -o '"code":[0-9]*' | head -1 | cut -d':' -f2 || echo "")
MSG_ID=$(echo "$SEND_RESP" | grep -o '"message_id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")

if [ "$SEND_CODE" = "0" ] && [ -n "$MSG_ID" ]; then
  echo "✅ 消息发送成功"
  echo "   message_id: $MSG_ID"
  echo "   open_id:    $OPEN_ID"
else
  echo "❌ 消息发送失败"
  echo "   响应: $SEND_RESP"
  exit 1
fi
