#!/bin/sh
# wb2api 部署验证四连：探活 / 模型表与烧分防护 / 账号 / 真实推理(免费档)
# 用法: sh scripts/verify.sh [端口] [API key]   默认 7863 / change-me-local-key
PORT="${1:-7863}"
KEY="${2:-change-me-local-key}"
H="Authorization: Bearer ${KEY}"
BASE="http://127.0.0.1:${PORT}"
PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "[1/4] 探活 /panel/api/overview（注意: /health 不存在，404 是正常的）"
ov=$(curl -s -m 5 -H "$H" "$BASE/panel/api/overview")
echo "$ov" | grep -q '"accounts"' && ok "overview 200" || bad "overview 异常: $(echo "$ov" | head -c 120)"

echo "[2/4] 模型表 + 烧分防护"
echo "$ov" | grep -q '"healthy":1' && ok "账号健康" || bad "无健康账号"
hidden=$(curl -s -m 5 -H "$H" "$BASE/panel/api/config" \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['config'];print(len(d.get('models',{}).get('hidden',[])),d.get('pool',{}).get('credit_floor'))")
h_n=${hidden%% *}; floor=${hidden##* }
[ "$h_n" -ge 12 ] 2>/dev/null && ok "hidden $h_n 个高倍率模型" || bad "hidden=$h_n（防护未生效）"
[ "$floor" != "None" ] && [ -n "$floor" ] && ok "credit_floor=$floor" || bad "credit_floor 未设置"

echo "[3/4] 高倍率模型泄漏扫描"
leak=$(curl -s -m 5 -H "$H" "$BASE/v1/models" | python3 -c "
import json,sys
ids=[m['id'] for m in json.load(sys.stdin)['data']]
bad={'gpt-6-astra','gpt-6-astra-pro','gpt-6-sol-pro','gpt-5.5','gpt-5.6-sol','gpt-5.6-terra','gpt-5.4','kimi-k3','kimi-k2.8-preview','grok-4.7','primary-model','deep-model'}
print(','.join(i for i in ids if i.split(':')[-1] in bad) or 'CLEAN')")
[ "$leak" = "CLEAN" ] && ok "无泄漏" || bad "泄漏: $leak"

echo "[4/4] 真实推理（免费档 global:hy3，x0 不烧分）"
resp=$(curl -s -m 90 -o /tmp/_wb_verify.json -w '%{http_code}' -X POST "$BASE/v1/chat/completions" \
  -H "$H" -H 'Content-Type: application/json' \
  -d '{"model":"global:hy3","messages":[{"role":"user","content":"reply with exactly: PONG"}],"max_tokens":30}')
if [ "$resp" = "200" ] && grep -q PONG /tmp/_wb_verify.json; then
  ok "chat 200 + PONG"
else
  bad "code=$resp body=$(head -c 150 /tmp/_wb_verify.json 2>/dev/null)"
fi

echo
echo "结果: 通过 $PASS · 失败 $FAIL"
[ "$FAIL" -eq 0 ]
