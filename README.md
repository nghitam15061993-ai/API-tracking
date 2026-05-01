# AWP API Monitor — GitHub Actions

Tự động ping API minework.net mỗi 20 phút trên GitHub's servers (free), gửi alert qua Telegram khi API down hoặc recover. Không cần chạy Python trên máy local.

## Cách hoạt động

- GitHub Actions chạy `monitor.sh` mỗi 20 phút (cron)
- Script ping API → kiểm tra UP/DOWN
- So sánh với state lần trước (lưu trong GitHub Repository Variable)
- Chỉ gửi Telegram alert khi **state thay đổi** (UP→DOWN hoặc DOWN→UP)
- Không spam mỗi 20 phút khi API ổn định

## Setup (lần đầu, ~5 phút)

### 1. Tạo Telegram bot

- Mở Telegram, tìm `@BotFather`
- Gửi `/newbot`, đặt tên bot
- Lưu lại **bot token** (dạng `123456789:ABC-DEF...`)

### 2. Lấy chat ID

- Gửi 1 tin nhắn bất kỳ tới bot vừa tạo (hoặc add bot vào group rồi nhắn trong group)
- Mở: `https://api.telegram.org/bot<TOKEN>/getUpdates` (thay `<TOKEN>` bằng bot token)
- Tìm `"chat":{"id":<NUMBER>}` — đó là chat ID
  - Group ID là số âm (vd `-1001234567890`)
  - Chat riêng là số dương

### 3. Tạo GitHub repo

- Tạo **public repo** mới trên github.com (public để được dùng Actions miễn phí không giới hạn)
- Upload 2 file vào repo:
  - `.github/workflows/monitor.yml`
  - `monitor.sh`

### 4. Add secrets vào repo

Vào repo → **Settings** → **Secrets and variables** → **Actions** → tab **Secrets** → **New repository secret**:

| Secret name | Value |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Bot token từ bước 1 |
| `TELEGRAM_CHAT_ID` | Chat ID từ bước 2 |

### 5. Cấp permission cho workflow ghi Variable

Vào repo → **Settings** → **Actions** → **General** → kéo xuống **Workflow permissions**:

- Chọn **Read and write permissions**
- Save

(Workflow cần ghi Variable để lưu state UP/DOWN giữa các lần chạy)

### 6. Test

- Vào tab **Actions** trong repo
- Chọn workflow **AWP API Monitor** ở sidebar trái
- Click **Run workflow** → **Run workflow**
- Đợi 20-30s → check log
- Nếu API đang down hoặc đây là lần chạy đầu → bạn nên nhận tin Telegram

Sau đó workflow sẽ tự chạy mỗi 20 phút.

## Customize

### Đổi endpoint

Thay vì sửa file, dùng GitHub Variable:

- Repo → **Settings** → **Secrets and variables** → **Actions** → tab **Variables**
- New variable: name = `API_URL`, value = endpoint mới (ví dụ `https://api.minework.net/api/health`)

### Đổi interval

Sửa `cron` trong `monitor.yml`:

```yaml
- cron: '*/10 * * * *'   # mỗi 10 phút
- cron: '0 * * * *'      # mỗi giờ tròn
- cron: '*/20 * * * *'   # mỗi 20 phút (mặc định)
```

Lưu ý: GitHub có thể delay cron 5-15 phút khi load cao. Nhỏ hơn 5 phút không recommend.

### Tắt monitor tạm thời

Vào tab **Actions** → workflow → click `…` → **Disable workflow**

## Troubleshooting

**Không nhận được alert:**
- Check tab Actions xem workflow có chạy không
- Click vào run → xem log step "Probe API and notify"
- Đảm bảo bạn đã nhắn tin với bot trước (bot mới không thể gửi tin tới user nếu user chưa start)

**Cron không trigger:**
- GitHub Actions cron có thể bị delay hoặc skip khi server load cao
- Public repo unlimited; private repo 2,000 phút/tháng (mỗi run ~30s, tổng ~12 phút/ngày → đủ trong giới hạn)
- Workflow phải có activity trong 60 ngày, nếu không sẽ tự disable. Activity = bất kỳ commit nào, hoặc enable lại.

**State không persist:**
- Đảm bảo step 5 đã làm: workflow permission = read/write
- Check tab Variables xem có `MONITOR_STATE` không (sau lần chạy đầu)

## Free quota

| Repo loại | Actions miễn phí |
|---|---|
| Public | Unlimited |
| Private | 2,000 phút/tháng |

Mỗi run ~30 giây. 20 phút × 24h × 30 ngày = 2,160 runs/tháng = ~18 giờ chạy. Public repo: không lo. Private: vừa tròn quota, OK nếu chỉ chạy monitor này.
