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
- **提醒功能**:可以請小毒「一段時間後」或「幾點」提醒你做某件事,支援模糊時間(「晚上」「明天早上」會依當下實際時間推算)跟口語簡寫(例如「8.提醒我打球」會理解成 8 點)
  - 同時最多 3 則還沒到期的提醒,單則最多設在 3 天以內,超過會請對方縮短時間
  - 可以取消或修改既有的提醒(「取消提醒」「改成半小時後」),Gemini 看得到目前有效的提醒清單,取消/修改失敗時會誠實告知,不會謊報成功
  - 提醒資料存在 Supabase(持久化,撐得過服務重啟),不是存在記憶體
  - 送達機制是「雙保險」:設定提醒時會額外在 cron-job.org 建立一個精準對到到期時間的一次性排程,時間一到就準時 ping 回伺服器主動推播;同時 UptimeRobot 既有的 5 分鐘保活輪詢也會順便檢查有沒有漏掉的到期提醒,當作最後一層保底
  - 推播額度不夠時(見下方額度保護),不會硬推,會在使用者下次主動聊天時用免費的 Reply API 補提一次
- **推播額度監控**:LINE 的 Push API 每月有 200 則免費額度,用量每跨過 25 的倍數,或到達自動推播上限(165 則,留 35 則餘裕給非提醒用途)時,會寄一封 email 通知,避免不知不覺用超
- **額度保護**:Gemini 429(額度超過)時,連續回覆最多 2 次罐頭吐槽,之後閉嘴到額度重置為止(依使用者各自獨立計算,不會互相拖累)
- **人設防護**:system prompt 裡明確禁止髒話、禁止洩漏規則本身,並針對「提到老闆」有特別的恭敬語氣規則
- **對話紀錄**:每則訊息與回覆都會印到 stdout,可在 Render Logs 查看(免費方案保留 7 天)

## 你需要先準備的環境變數

以下全部是**必要**的,少了任一個服務會直接啟動失敗(沒有預設值):

1. **LINE_CHANNEL_SECRET** 和 **LINE_CHANNEL_ACCESS_TOKEN**
   來自 LINE Developers Console 的 Messaging API channel(見下方步驟 A)。
2. **GEMINI_API_KEY**
   來自 Google AI Studio。**注意**:如果同帳號下還有其他用 Gemini 的專案,
   申請 Key 時要選「建立新 Project」,額度是綁 Project 不是綁 Key,
   共用同一個 Project 會互相搶額度。
3. **SUPABASE_URL** 和 **SUPABASE_SERVICE_KEY**
   來自 Supabase 免費專案,用來持久化存提醒資料跟額度通知的寄送狀態(見下方步驟 B)。
4. **EMAIL_ADDRESS** 和 **EMAIL_APP_PASSWORD**
   一組 Gmail 帳號 + App Password(不是登入密碼本身),用來寄推播額度用量通知信(見下方步驟 C)。
5. **CRON_JOB_ORG_API_KEY**
   來自 cron-job.org 免費帳號,用來讓提醒精準送達,而不是只靠 UptimeRobot 固定 5 分鐘輪詢(見下方步驟 D)。
6. **REMINDER_TICK_SECRET**
   自己隨便生一串隨機字串就好,不用去哪裡申請,只是用來驗證打進 `/reminder-tick`
   這個路由的真的是 cron-job.org,不是被人亂猜到路徑打進來的。

另外有個選填的環境變數 `BASE_URL`(預設是部署出來的 Render 服務網址),
用來組表情包圖片、提醒回呼(`/reminder-tick`)的公開網址,只有網址跟預設值不同時才需要設定。

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
5. Webhook URL 先留著,等 Render 部署好拿到網址再填(步驟 G)。

---

## 步驟 B:建立 Supabase 專案跟資料表

1. 到 https://supabase.com/ 註冊,建立一個免費專案。
2. 到 **Project Settings → API**,記下 **Project URL**(`SUPABASE_URL`)和
   **service_role key**(`SUPABASE_SERVICE_KEY`,注意不是 anon key,而且這把 key
   會繞過 RLS,務必當成機密處理,不要進 git)。
3. 到 **SQL Editor**,執行以下建表語法:

```sql
create table reminders (
  id bigint generated always as identity primary key,
  user_id text not null,
  remind_at timestamptz not null,
  message text not null,
  delivered boolean not null default false,
  created_at timestamptz not null default now(),
  cron_job_id bigint
);
create index reminders_due_idx on reminders (remind_at) where delivered = false;
alter table reminders enable row level security;
grant select, insert, update on reminders to service_role;

create table quota_alert_state (
  id int primary key,
  month text not null default '',
  last_notified_threshold int not null default 0
);
insert into quota_alert_state (id) values (1);
alter table quota_alert_state enable row level security;
grant select, insert, update on quota_alert_state to service_role;
```

> 兩張表都只 grant `select`/`insert`/`update` 給 `service_role`,刻意不給 `delete`——
> 提醒被取消或送達,一律是把 `delivered` 改成 `true`,不會真的刪列,避免誤刪資料。

---

## 步驟 C:申請 Gmail App Password

1. 用一個 Gmail 帳號(可以是專門申請的,不一定要用主帳號),到帳號設定開啟兩步驟驗證。
2. 到 https://myaccount.google.com/apppasswords 產生一組 App Password(16 碼,跟登入密碼不同)。
3. `EMAIL_ADDRESS` 填這個 Gmail 帳號,`EMAIL_APP_PASSWORD` 填剛剛產生的 App Password。

---

## 步驟 D:申請 cron-job.org API Key

1. 到 https://cron-job.org/ 註冊一個免費帳號。
2. 登入後到 **Settings → API**,按 **Create API Key**。
3. Title 隨便填,**IP Address Restriction 留空**(伺服器在 Render,IP 是動態的,限制反而會擋到自己)。
4. 按 **Create API Key**,產生的值就是 `CRON_JOB_ORG_API_KEY`(通常只會完整顯示這一次,記得存好)。
5. 自己另外生一串隨機字串當 `REMINDER_TICK_SECRET`(跟 cron-job.org 無關,純粹是自訂的驗證密鑰)。

---

## 步驟 E:本地測試(可選,但建議先跑一次)

```bash
pip install -r requirements.txt

export LINE_CHANNEL_SECRET="..."
export LINE_CHANNEL_ACCESS_TOKEN="..."
export GEMINI_API_KEY="..."
export SUPABASE_URL="..."
export SUPABASE_SERVICE_KEY="..."
export EMAIL_ADDRESS="..."
export EMAIL_APP_PASSWORD="..."
export CRON_JOB_ORG_API_KEY="..."
export REMINDER_TICK_SECRET="..."

uvicorn main:app --reload --port 8080
```

打開 `http://127.0.0.1:8080/` 應該會看到 `{"status":"ok"}`,代表服務正常啟動。
要實際接 LINE webhook 測試,需要一個公開網址(例如部署到 Render 後直接測,
比在本機用臨時通道工具測試更直接)。

---

## 步驟 F:部署到 Render(免費、不用綁卡)

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
   - `SUPABASE_URL` = 你的值
   - `SUPABASE_SERVICE_KEY` = 你的值
   - `EMAIL_ADDRESS` = 你的值
   - `EMAIL_APP_PASSWORD` = 你的值
   - `CRON_JOB_ORG_API_KEY` = 你的值
   - `REMINDER_TICK_SECRET` = 你的值
6. 按 **Create Web Service**,等它 build + deploy 完成。

完成後 Render 會給你一個網址,格式類似 `https://<你的服務名稱>.onrender.com`。

> **免費方案會休眠**:閒置 15 分鐘會休眠,下一則訊息要等 30–60 秒冷啟動才有反應,
> 之後對話就即時。可以用 [UptimeRobot](https://uptimerobot.com/) 免費方案
> 每 5 分鐘 ping 一次根目錄(`/`)這個健康檢查路由來保持喚醒,詳見專案報告。

---

## 步驟 G:把網址接回 LINE

回到 LINE Developers Console → Messaging API 分頁 → Webhook URL,填入
Render 給你的服務網址,結尾加上 `/callback`(例如 `https://<你的服務名稱>.onrender.com/callback`)。

按 **Verify** 確認能連通,並把 **Use webhook** 打開。

> 注意:按 Verify 時,如果 service 正在休眠,第一次可能因冷啟動而 timeout,
> 稍等 30 秒再按一次即可。

---

## 完成後

用手機加自己的官方帳號好友,傳一句話,應該會收到 Gemini 用「小毒」語氣的回覆。

## 想擴充功能

- **加新表情包**:把圖片(< 1MB,LINE 的限制)放進 `memes/` 資料夾,在 `main.py`
  的 `MEMES` 字典裡加一筆 `{id: {"file": "檔名", "trigger": "什麼情境該用"}}` 就好。
- **調整人設**:改 `main.py` 裡的 `SYSTEM_PROMPT_BASE`。
- **細節設定都是常數**:對話記憶長度、各種輸入上限、429 罐頭回覆、表情包發送機率、
  提醒的天數/則數上限、推播額度門檻等等,都是 `main.py` 檔案開頭的常數,方便單獨調整。

## 已知限制

- 對話記憶跟 429 額度限制狀態還是存在程式記憶體,服務重啟(重新部署)就會清空
  (提醒資料本身已經存在 Supabase,不受影響)
- 群組聊天(不是 1 對 1)沒有特別測試過
- cron-job.org 的精準推播只是「加速」,不是唯一保障——如果那次 API 呼叫失敗,
  UptimeRobot 的 5 分鐘輪詢仍然會接住,最多晚幾分鐘送達,不會整個漏掉

完整的架構圖、除錯過程、成本試算與資安檢查,見專案報告(Artifact)。
