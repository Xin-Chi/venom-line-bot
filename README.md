# Venom-Bot × LINE

一個接上 LINE 官方帳號的聊天 bot「小毒」,後端用 Gemini Flash-Lite 生成回覆。
架構刻意把「LINE 整合」和「回覆從哪來」解耦 —— 之後要換成自己 fine-tune
的模型,只需改 `main.py` 的 `generate_reply()`,其餘不動。

## 目前功能

- **對話記憶**:每個 LINE 使用者各自保留最近 12 輪對話,存在記憶體(服務重啟會清空)
- **多模態輸入**:文字、貼圖、圖片、語音、影片、PDF 文件都能處理
  - 語音超過 2 分 01 秒、影片超過 31 秒、PDF 超過 6 頁或 20MB,一律不送 Gemini,直接吐槽回覆
  - 影片一律用 Gemini 低畫質模式處理,省 token
- **連結理解**:訊息裡有網址時,會用 Gemini 的 `url_context` 工具讀取網頁內容
- **表情包回覆**:內建一組表情包(`memes/` 資料夾 + `main.py` 的 `MEMES` 字典),Gemini 會依情境判斷要不要附圖,情境符合時也只有一定機率真的附上(`MEME_SEND_CHANCE`),避免太頻繁
- **額度保護**:Gemini 429(額度超過)時,連續回覆最多 2 次罐頭吐槽,之後閉嘴到額度重置為止(依使用者各自獨立計算,不會互相拖累)
- **人設防護**:system prompt 裡明確禁止髒話、禁止洩漏規則本身,並針對「提到老闆」有特別的恭敬語氣規則
- **對話紀錄**:每則訊息與回覆都會印到 stdout,可在 Render Logs 查看(免費方案保留 7 天)

## 你需要先準備的三把鑰匙

1. **LINE_CHANNEL_SECRET** 和 **LINE_CHANNEL_ACCESS_TOKEN**
   來自 LINE Developers Console 的 Messaging API channel(見下方步驟 A)。
2. **GEMINI_API_KEY**
   來自 Google AI Studio。**注意**:如果同帳號下還有其他用 Gemini 的專案,
   申請 Key 時要選「建立新 Project」,額度是綁 Project 不是綁 Key,
   共用同一個 Project 會互相搶額度。

另外有個選填的環境變數 `BASE_URL`(預設是 `https://venom-line-bot.onrender.com`),
用來組表情包圖片的公開網址,只有網址跟預設值不同時才需要設定。

---

## 步驟 A:開一個 LINE 官方帳號 + Messaging API channel

1. 到 https://developers.line.biz/ 用 LINE 帳號登入,建立一個 Provider。
2. 在該 Provider 下建立一個 **Messaging API** channel。
3. 進入 channel 的 **Messaging API** 分頁:
   - 記下 **Channel access token**(按 Issue 產生) → 這是 `LINE_CHANNEL_ACCESS_TOKEN`
   - 到 **Basic settings** 分頁記下 **Channel secret** → 這是 `LINE_CHANNEL_SECRET`
4. 到 LINE Official Account Manager(manager.line.biz)的「設定 → 回應設定」:
   - **Webhook**:開啟(讓 LINE 把訊息轉發給這支程式)
   - **自動回應訊息**:關閉(不然會跟 bot 打架)
   - **聊天**:開啟或關閉都可以 —— 開啟的話,你能在「聊天」分頁看到跟每個好友的完整對話紀錄(不影響 bot 自動回覆,兩者可以並存)
5. Webhook URL 先留著,等 Render 部署好拿到網址再填(步驟 D)。

---

## 步驟 B:本地測試(可選,但建議先跑一次)

```bash
pip install -r requirements.txt

export LINE_CHANNEL_SECRET="..."
export LINE_CHANNEL_ACCESS_TOKEN="..."
export GEMINI_API_KEY="..."

uvicorn main:app --reload --port 8080
```

打開 `http://127.0.0.1:8080/` 應該會看到 `{"status":"ok"}`,代表服務正常啟動。
要實際接 LINE webhook 測試,需要一個公開網址(例如部署到 Render 後直接測,
比在本機用臨時通道工具測試更直接)。

---

## 步驟 C:部署到 Render(免費、不用綁卡)

Render 從 GitHub repo 自動部署。免費方案額度用完會暫停服務,不會產生帳單。

前置:先把這個專案 push 到一個 GitHub repo(可以是 private)。

1. 到 https://render.com/ 用 GitHub 帳號註冊/登入(不用綁卡)。
2. 點 **New +** → **Web Service**。
3. 連結並選擇你的 GitHub repo(private repo 也沒問題,不影響部署出來的服務公開與否)。
4. 設定:
   - **Runtime**:Python(通常會自動偵測)
   - **Build Command**:`pip install -r requirements.txt`
   - **Start Command**:`uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Instance Type**:選 **Free**
5. 往下找 **Environment Variables**,新增:
   - `LINE_CHANNEL_SECRET` = 你的值
   - `LINE_CHANNEL_ACCESS_TOKEN` = 你的值
   - `GEMINI_API_KEY` = 你的值
6. 按 **Create Web Service**,等它 build + deploy 完成。

完成後 Render 會給你一個網址,例如:
`https://venom-line-bot.onrender.com`

> **免費方案會休眠**:閒置 15 分鐘會休眠,下一則訊息要等 30–60 秒冷啟動才有反應,
> 之後對話就即時。可以用 [UptimeRobot](https://uptimerobot.com/) 免費方案
> 每 5 分鐘 ping 一次 `/` 這個健康檢查路由來保持喚醒,詳見專案報告。

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

## 想擴充功能

- **加新表情包**:把圖片(< 1MB,LINE 的限制)放進 `memes/` 資料夾,在 `main.py`
  的 `MEMES` 字典裡加一筆 `{id: {"file": "檔名", "trigger": "什麼情境該用"}}` 就好。
- **調整人設**:改 `main.py` 裡的 `SYSTEM_PROMPT`。
- **細節設定都是常數**:對話記憶長度、各種輸入上限、429 罐頭回覆、表情包發送機率
  等等,都是 `main.py` 檔案開頭的常數,方便單獨調整。

## 已知限制

- 對話記憶跟額度限制狀態都存在程式記憶體,服務重啟(重新部署)就會清空
- 群組聊天(不是 1 對 1)沒有特別測試過
- 沒有接資料庫,無法做真正長期的記憶

完整的架構圖、除錯過程、成本試算與資安檢查,見專案報告(Artifact)。
