# Venom-Bot × LINE (Stage 1: Gemini backend)

一個接上 LINE 官方帳號的聊天 bot,後端用 Gemini Flash-Lite 生成回覆。
架構刻意把「LINE 整合」和「回覆從哪來」解耦 —— 之後要換成自己 fine-tune
的模型,只需改 `main.py` 的 `generate_reply()`,其餘不動。

---

## 你需要先準備的三把鑰匙

1. **LINE_CHANNEL_SECRET** 和 **LINE_CHANNEL_ACCESS_TOKEN**
   來自 LINE Developers Console 的 Messaging API channel(見下方步驟 A)。
2. **GEMINI_API_KEY**
   來自 Google AI Studio(你做 AI 新聞 pipeline 時應該已經有了)。

---

## 步驟 A:開一個 LINE 官方帳號 + Messaging API channel

1. 到 https://developers.line.biz/ 用 LINE 帳號登入,建立一個 Provider。
2. 在該 Provider 下建立一個 **Messaging API** channel。
3. 進入 channel 的 **Messaging API** 分頁:
   - 記下 **Channel access token**(按 Issue 產生) → 這是 `LINE_CHANNEL_ACCESS_TOKEN`
   - 到 **Basic settings** 分頁記下 **Channel secret** → 這是 `LINE_CHANNEL_SECRET`
4. 同一分頁把「自動回覆訊息 / 加入好友的問候訊息」關掉(不然會跟 bot 打架)。
5. Webhook URL 先留著,等 Cloud Run 部署好拿到網址再填(步驟 C)。

---

## 步驟 B:本地測試(可選,但建議先跑一次)

```bash
pip install -r requirements.txt

export LINE_CHANNEL_SECRET="..."
export LINE_CHANNEL_ACCESS_TOKEN="..."
export GEMINI_API_KEY="..."

uvicorn main:app --reload --port 8080
```

用 ngrok 開一條臨時通道,把它當 webhook URL 貼回 LINE 測試:
```bash
ngrok http 8080
# 拿到 https://xxxx.ngrok-free.app,LINE webhook 填 https://xxxx.ngrok-free.app/callback
```

---

## 步驟 C:部署到 Render(免費、不用綁卡)

Render 從 GitHub repo 自動部署,不需要 Dockerfile,也不用信用卡。
用量若超過額度會「暫停服務」而非收費,所以零帳單風險。

前置:先把這個專案 push 到一個 GitHub repo。

1. 到 https://render.com/ 用 GitHub 帳號註冊/登入(不用綁卡)。
2. 點 **New +** → **Web Service**。
3. 連結並選擇你的 GitHub repo。
4. 設定:
   - **Runtime**:Python(通常會自動偵測)
   - **Build Command**:`pip install -r requirements.txt`
   - **Start Command**:`uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Instance Type**:選 **Free**
5. 往下找 **Environment Variables**,新增三個:
   - `LINE_CHANNEL_SECRET` = 你的值
   - `LINE_CHANNEL_ACCESS_TOKEN` = 你的值
   - `GEMINI_API_KEY` = 你的值
6. 按 **Create Web Service**,等它 build + deploy 完成。

完成後 Render 會給你一個網址,例如:
`https://venom-line-bot.onrender.com`

> 提醒:免費 service 閒置 15 分鐘會休眠,下一則訊息要等 30–60 秒冷啟動,
> 之後對話就即時。這是免費方案的正常行為。

> Dockerfile 在 Render 部署時用不到(它靠 Build/Start Command),
> 但留著不影響,之後若想改用其他平台可派上用場。

---

## 步驟 D:把網址接回 LINE

回到 LINE Developers Console → Messaging API 分頁 → Webhook URL,填入:
```
https://venom-line-bot.onrender.com/callback
```
(換成 Render 給你的實際網址,結尾記得加 `/callback`)

按 **Verify** 確認能連通,並把 **Use webhook** 打開。

> 注意:按 Verify 時,如果 service 正在休眠,第一次可能因冷啟動而 timeout,
> 稍等 30 秒再按一次即可。

---

## 完成後

用手機加自己的官方帳號好友,傳一句話,應該會收到 Gemini 用「小毒」語氣的回覆。

## 下一步(之後的階段)

- 階段二:細調 `SYSTEM_PROMPT`,看 prompt 能把風格逼近到幾成。
- 階段三:把 `generate_reply()` 換成你 fine-tune 的 Venom-Bot 模型
  (這時才需要動用 GPU 部署 / serverless 推論)。
