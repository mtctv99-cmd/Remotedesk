# Cẩm nang test LAN — DeskAgent (fork RustDesk nội bộ)

Tài liệu hướng dẫn chạy test các tính năng của DeskAgent trong mạng LAN với 2 máy:
**Máy A** (admin + server) và **Máy B** (máy được điều khiển / client test).

> **Quy ước**
> - `<IP-A>` = địa chỉ IPv4 LAN của máy A. Lấy bằng lệnh `ipconfig` trên máy A (dòng *IPv4 Address*, ví dụ `192.168.1.10`). Thay thật cả dấu `<>` khi gõ lệnh.
> - `<SUBNET-LAN>` = dải mạng nội bộ, ví dụ `192.168.1.0/24` (chỉ dùng ở mục Bảo mật).
> - Mọi đường dẫn trong lệnh là đường dẫn thật trên repo; các bước test cần **quyền Administrator** khi mở firewall / cài driver.

> **Trạng thái build tại thời điểm soạn tài liệu (30/09/2026)** — đã kiểm tra trực tiếp trên máy:
> - ✅ Server: `C:\Users\chu.mai\Desktop\Remote\tools\server\x86_64\` có sẵn `hbbs.exe`, `hbbr.exe`, `run-server.cmd`.
> - ⚠️ Client: `C:\Users\chu.mai\Desktop\Remote\DeskAgent\flutter\build\windows\x64\runner\Release\` **chưa tồn tại** — exe sẽ có sau khi bật Developer Mode của Windows và build Flutter (`flutter build windows --release`, script `build.py:976`). Tên exe do `BINARY_NAME` quyết định, hiện là `rustdesk.exe` (`flutter\windows\CMakeLists.txt:7`).
> - ⚠️ Manager: `C:\Users\chu.mai\Desktop\Remote\DeskAgent\manager\target\release\deskagent-manager.exe` **chưa có** — hiện chỉ có bản debug tại `...\manager\target\debug\deskagent-manager.exe`. Chạy `cargo build --release` trong thư mục `DeskAgent\manager` để có đúng đường dẫn release dùng trong cẩm nang này.

---

## 1. Chuẩn bị

### 1.1. Hai máy trong cùng LAN

| Máy | Vai trò | Cần có |
|---|---|---|
| **Máy A** | Admin + chạy Manager + chạy server hbbs/hbbr | Thư mục `tools\server\x86_64`, thư mục `DeskAgent\manager` đã build, trình duyệt |
| **Máy B** | Client test (máy được điều khiển) | DeskAgent client đã build (`Release\rustdesk.exe` + `librustdesk.dll`) |

Cả 2 máy phải thấy được nhau: từ máy B chạy `ping <IP-A>` phải có reply.

### 1.2. Checklist mở firewall trên máy A (chạy cmd với quyền Administrator)

```bat
netsh advfirewall firewall add rule name="DeskAgent hbbs-hbbr TCP" dir=in action=allow protocol=TCP localport=21115-21119
netsh advfirewall firewall add rule name="DeskAgent hbbs-hbbr UDP" dir=in action=allow protocol=UDP localport=21115-21119
netsh advfirewall firewall add rule name="DeskAgent Manager TCP" dir=in action=allow protocol=TCP localport=8080
```

Ý nghĩa port:

| Port | Giao thức | Dịch vụ |
|---|---|---|
| 21115–21119 | TCP + UDP | hbbs (ID server) + hbbr (relay) — 21116 là ID/rendezvous, 21117 là relay |
| 8080 | TCP | Manager (console admin + API client) |

**Cách xác nhận đã OK:**
1. `netsh advfirewall firewall show rule name="DeskAgent Manager TCP"` — hiện rule với `Enabled: Yes`, `LocalPort: 8080` (làm tương tự cho 2 rule còn lại).
2. Từ máy B kiểm tra kết nối thực tế:
   ```bat
   powershell -c "Test-NetConnection <IP-A> -Port 21116"
   powershell -c "Test-NetConnection <IP-A> -Port 8080"
   ```
   Cả hai phải trả về `TcpTestSucceeded : True` (cần Manager/hbbs đang chạy — xem mục 2, 3).

---

## 2. Chạy Manager trên máy A

### 2.1. Lệnh khởi động (cmd) — set env từng biến

```bat
cd /d C:\Users\chu.mai\Desktop\Remote\DeskAgent\manager\target\release

set DESKAGENT_MANAGER_BIND=0.0.0.0:8080
set DESKAGENT_AI_URL=https://api.openai.com/v1
set DESKAGENT_AI_KEY=sk-...key-cua-ban...
set DESKAGENT_AI_MODEL=gpt-4o-mini
set DESKAGENT_AI_HOSTS=api.openai.com

deskagent-manager.exe
```

Bảng biến môi trường:

| Biến | Ý nghĩa | Mặc định khi bỏ trống |
|---|---|---|
| `DESKAGENT_MANAGER_BIND` | Địa chỉ bind của Manager | `0.0.0.0:8080` |
| `DESKAGENT_AI_URL` | Endpoint OpenAI-compatible (chat completions) | — (bot tắt) |
| `DESKAGENT_AI_KEY` | API key, gửi kèm header `Authorization: Bearer` | — (bot tắt) |
| `DESKAGENT_AI_MODEL` | Tên model | — (bot tắt) |
| `DESKAGENT_AI_HOSTS` | Allowlist host AI, phân tách bằng dấu phẩy, **chỉ tên host, không có port** | không giới hạn tên |

**Lưu ý quan trọng:** Manager có cơ chế chống SSRF cho proxy AI — host AI phải là **host public** (bị chặn nếu là `localhost`, `.local`, hoặc IP private `10.x`, `172.16–31.x`, `192.168.x`, `100.64–127.x`). `DESKAGENT_AI_HOSTS` chỉ giới hạn *tên được phép*, không miễn trừ việc kiểm tra private. Nếu công ty dùng AI nội bộ trong LAN thì proxy sẽ từ chối — dùng endpoint public cho test.

`manager.db` (SQLite) được tạo **cạnh thư mục đang chạy** (`cd` trước khi chạy exe). Muốn reset dữ liệu test: dừng Manager, xoá `manager.db`, chạy lại.

### 2.2. Console admin

Mở trình duyệt trên máy A (và trên máy B để kiểm tra truy cập LAN): `http://<IP-A>:8080/`.

Console gồm **4 vùng** (sidebar bên trái):

1. **Tổng quan** — thẻ thống kê: số máy khách online/tổng số, số hội thoại, số job deploy + mục "Trạng thái hệ thống" (thời điểm cập nhật gần nhất).
2. **Máy khách** — danh sách máy đã đăng ký (hostname, OS, kiến trúc, thời gian cập nhật); bấm vào máy để xem chi tiết: inventory JSON (System Info) và bảng event log (tối đa 500 dòng mới nhất). Có ô tìm kiếm + nút Làm mới.
3. **Hội thoại** — danh sách hội thoại từ client; chọn 1 hội thoại để xem luồng tin nhắn, có nút **Claim** (nhận xử lý, bot ngừng trả lời) và nút đóng hội thoại, ô nhập để admin trả lời trực tiếp.
4. **Job deploy** — form tạo job (chọn máy đích hoặc "Tất cả máy khách", lệnh silent command, Package URL / Package path tuỳ chọn) + bảng "Danh sách job" hiển thị ID, máy khách, gói, lệnh, **trạng thái**, **kết quả**, thời điểm tạo.

**Cách xác nhận đã OK:**
- Cửa sổ cmd của Manager in đúng 2 dòng: `deskagent-manager listening on http://0.0.0.0:8080` và một trong hai dòng `AI proxy enabled: endpoint=... model=...` (đã set đủ 3 biến AI) hoặc `AI bot disabled: DESKAGENT_AI_URL / DESKAGENT_AI_KEY / DESKAGENT_AI_MODEL not all set`.
- File `manager.db` xuất hiện trong `C:\Users\chu.mai\Desktop\Remote\DeskAgent\manager\target\release\`.
- Console mở được từ **máy B** tại `http://<IP-A>:8080/` (chứng tỏ firewall + bind OK).

---

## 3. Chạy hbbs/hbbr và lấy key

Trên máy A, chạy file có sẵn:

```bat
C:\Users\chu.mai\Desktop\Remote\tools\server\x86_64\run-server.cmd
```

Script tự chạy `hbbs.exe` (ID server) + `hbbr.exe` (relay) trong 2 cửa sổ riêng, và in ra cấu hình cần nhập bên client.

**Cách xác nhận đã OK:**
- Cuối output script hiện nội dung key public; file `id_ed25519.pub` (và `id_ed25519`) được **tự sinh lần đầu chạy** trong cùng thư mục `x86_64\`.
- 2 cửa sổ `hbbs` / `hbbr` còn mở và không báo lỗi bind port (nếu bị chiếm port, tắt process cũ hoặc đổi máy).
- Từ máy B: `powershell -c "Test-NetConnection <IP-A> -Port 21116"` → `TcpTestSucceeded : True`.
- Cất nội dung `id_ed25519.pub` (1 dòng base64) để dùng ở bước 4. Xem lại bất kỳ lúc nào: `type C:\Users\chu.mai\Desktop\Remote\tools\server\x86_64\id_ed25519.pub`.

---

## 4. Cài DeskAgent lên máy B

### 4.1. Sao chép và cấu hình ID server / relay / key qua UI

1. Copy nguyên thư mục `C:\Users\chu.mai\Desktop\Remote\DeskAgent\flutter\build\windows\x64\runner\Release\` sang máy B (exe là `rustdesk.exe` — tên DeskAgent của build hiện tại).
2. Chạy `rustdesk.exe` trên máy B.
3. Vào **Settings → Network → ID/Relay Server** (hoặc màn hình chính → menu ID server) và nhập:
   - **ID server:** `<IP-A>:21116`
   - **Relay:** `<IP-A>:21117`
   - **Key:** toàn bộ nội dung file `id_ed25519.pub` (dán nguyên dòng base64, không kèm tên file).

**Cách xác nhận đã OK:** chỉ báo trạng thái server trên app chuyển sang màu xanh / "Ready"; máy B đã có ID số hiển thị trên màn hình chính.

### 4.2. Trỏ client về Manager của máy A — đặt env `DESKAGENT_MANAGER_URL`

Daemon của client (poll Manager mỗi 30 giây: register lúc chạy lần đầu, upload inventory + events mỗi 10 phút, nhận deploy job) đọc biến `DESKAGENT_MANAGER_URL` **của process chạy client**. Không set thì mặc định `http://127.0.0.1:8080` — tức là client sẽ tìm Manager trên chính máy B và không bao giờ thấy máy A.

**Cách 1 — `setx` (lưu vĩnh viễn cho user, áp dụng cho process khởi động sau đó):**

```bat
setx DESKAGENT_MANAGER_URL "http://<IP-A>:8080"
```

Sau đó **đóng hẳn** DeskAgent trên máy B (kiểm tra Task Manager không còn process nào của app) và chạy lại để process mới kế thừa biến.

**Cách 2 — chạy từ cmd (chỉ có hiệu lực cho phiên cmd này, tiện test lặp):**

```bat
cd /d C:\Users\chu.mai\Desktop\Remote\DeskAgent\flutter\build\windows\x64\runner\Release
set DESKAGENT_MANAGER_URL=http://<IP-A>:8080
rustdesk.exe
```

**Cách xác nhận đã OK:**
- Trên máy A, mở console `http://<IP-A>:8080/` → vùng **Máy khách** → máy B xuất hiện trong vòng ~30–60 giây với đúng hostname / OS / kiến trúc.
- Sau tối đa 10 phút (và ngay ở tick đầu tiên sau khi client khởi động), bấm vào máy B → thấy **inventory JSON** và **bảng events** có dữ liệu.
- Nếu máy B KHÔNG xuất hiện sau khi đã sửa env: xoá file `%LOCALAPPDATA%\DeskAgent\manager_client_id` trên máy B rồi khởi động lại client — client chỉ **register khi sinh ID mới**, nếu lần chạy trước đã trỏ sai URL thì ID cũ không tự đăng ký lại.

---

## 5. Checklist test từng tính năng

### 5.1. Điều khiển từ xa + truyền file (LAN direct)

- Trên máy A chạy `rustdesk.exe` (viewer), nhập ID của máy B, kết nối bằng mật khẩu tạm thời (hiện trên app máy B) hoặc mật khẩu thường.
- Chuyển sang **File Transfer** (icon truyền file trên thanh kết nối) để kéo–thả file 2 chiều.

**Cách xác nhận đã OK:** màn hình máy B hiển thị trọn vẹn trên máy A, chuột/phím phản hồi tức thì; file copy qua phiên chuyển successful và file xuất hiện đúng thư mục đích; giữ kết nối vài phút không tự ngắt.

### 5.2. System Info + Event Viewer trên app (máy B)

- Trên máy B: **Settings → tab DeskAgent** (chỉ hiện trên Windows) → thẻ **System Info** và thẻ **Event Viewer**.
- *System Info:* thông tin hostname, OS, phiên bản, kiến trúc của máy B.
- *Event Viewer:* các event cảnh báo/lỗi Windows gần đây.

**Cách xác nhận đã OK:** dữ liệu System Info khớp với `systeminfo` chạy bằng cmd; Event Viewer khớp với Windows Event Viewer (lọc Warning/Error/Critical) trên máy B.

### 5.3. Event / inventory hiện ở console

- Console máy A → **Máy khách** → chọn máy B.

**Cách xác nhận đã OK:** inventory JSON hiển thị hostname/OS trùng với mục 5.2; events nhận được chứa cùng các cảnh báo/lỗi vừa xem trên app. Nếu vừa mới bật client mà chưa thấy: chờ chu kỳ upload kế tiếp (mỗi 10 phút).

### 5.4. Chat AI

**Trường hợp 1 — có key (đã set `DESKAGENT_AI_URL/KEY/MODEL` ở mục 2):**

Từ bất kỳ máy nào trong LAN (PowerShell), tạo hội thoại và gửi 1 câu đơn giản:

```powershell
$m = "http://<IP-A>:8080"
$id = (Invoke-RestMethod -Method Post -Uri "$m/api/conversations" -ContentType "application/json" -Body '{}').conversation_id
Invoke-RestMethod -Method Post -Uri "$m/api/conversations/$id/messages" -ContentType "application/json" -Body '{"text":"Chao ban, gioi thieu ban than trong 1 cau"}'
```

**Xác nhận OK:** response trả về trường `reply` là câu trả lời AI; console → **Hội thoại** hiện đúng thread với tin user + tin bot.

**Trường hợp 2 — không có key (chạy Manager mà không set 3 biến AI):**

Lặp lại lệnh POST ở trên.

**Xác nhận OK:** `reply` trả về đúng chuỗi **"chưa cấu hình AI"**; console hiện tin bot với nội dung đó.

> **Lưu ý về chat trong app máy B:** trang AI Chat của app trỏ tới Manager bằng hằng số biên dịch `http://127.0.0.1:8080` (`flutter\lib\features\deskagent\deskagent_config.dart:5`). Trong thế giản 2 máy (Manager chạy trên A), chat trong app trên B sẽ báo lỗi *"Cannot reach the Manager at http://127.0.0.1:8080"* — đây là hành vi đúng của bản build hiện tại, không phải lỗi mạng. Test luồng hội thoại bằng REST như trên (kết quả vẫn hiển thị trên console), hoặc tạm chạy Manager trên chính máy B nếu muốn test qua UI app.

### 5.5. Admin Claim hội thoại → bot dừng → admin reply

1. Console → **Hội thoại** → chọn hội thoại ở mục 5.4 → nút **Claim**.
2. Gửi thêm 1 tin user bằng lệnh POST ở mục 5.4.
3. Tại console, gõ nội dung trả lời trong ô reply của thread.

**Cách xác nhận đã OK:**
- Sau Claim, message mới của user nhận `reply: null` (bot im lặng — đúng thiết kế: hội thoại đã claimed thì bot bỏ qua).
- Tin admin xuất hiện trong thread với sender `admin`; mọi message user tiếp theo vẫn chỉ nhận `null` từ bot (admin reply cũng tự giữ trạng thái claimed).

### 5.6. Deploy job

Console → **Job deploy** → **Tạo job deploy**:

| Trường | Giá trị ví dụ (an toàn) |
|---|---|
| Máy khách đích | chọn máy B (hoặc "Tất cả máy khách (all)") |
| Silent command | `echo DeskAgent job OK > "%PUBLIC%\deskagent_job_test.txt"` |
| Package path local (tuỳ chọn) | `C:\Windows\System32\notepad.exe` — **đường dẫn tính trên máy B**; kèm silent command `notepad.exe` để mở Notepad lên máy B (hiệu ứng nhìn thấy được) |
| Package URL (tuỳ chọn) | URL http/https tới file cài đặt/portable app đặt trên web server nội bộ của công ty |

Job được client tải về và thực thi qua `cmd /C`, đầu ra (exit code + stdout/stderr, tối đa 32KB) gửi ngược về Manager. Cơ chế job tải package: `package_url` → tải về `%TEMP%\DeskAgent\<job_id>\` trên máy B; `package_path` → dùng file có sẵn trên **máy B** và đặt working directory vào thư mục cha của nó.

> ⚠️ **Cấm test bằng lệnh phá hệ thống** (xoá file/thư mục, sửa registry, đổi mật khẩu, `format`, tắt service bảo vệ…). Job chạy thầm lặng với quyền của process client — chỉ tạo job với lệnh bạn hiểu rõ và có thể đảo ngược.

**Cách xác nhận đã OK:**
- File `%PUBLIC%\deskagent_job_test.txt` xuất hiện trên máy B với nội dung `DeskAgent job OK` (hoặc Notepad mở trên máy B nếu dùng ví dụ `notepad.exe`).
- Job được client nhận trong vòng ~30 giây (chu kỳ poll); console → **Job deploy** → Danh sách job hiện trạng thái `success` và ô Kết quả chứa `exit_code: 0` + stdout của lệnh.

### 5.7. Trạng thái job ở console

Vòng đời job hiển thị tại bảng "Danh sách job": `pending` (mới tạo) → `running` (client đã nhận qua poll) → `success` / `failed` (client đã gửi kết quả về). Nếu job lỗi, ô Kết quả hiển thị dòng `error: ...` hoặc output trình cài đặt — dùng chính ô này để chẩn đoán (xem mục 7).

**Cách xác nhận đã OK:** trạng thái chuyển đúng thứ tự trên và không quay về `pending` sau khi đã chạy (client không nhận lại job cũ ở poll kế tiếp).

---

## 6. Mẹo vận hành

### 6.1. Deploy màn hình ảo (virtual display) qua job

Hữu ích khi máy B là máy headless (không cắm màn hình) — client có sẵn tham số dòng lệnh `--install-idd` để cài RustDesk IDD virtual display driver. Tạo job:

- **Silent command:** `"C:\Program Files\DeskAgent\rustdesk.exe" --install-idd & C:\Tools\QRes.exe /x:1920 /y:1080 /r:60`
  (điều chỉnh đường dẫn exe theo nơi cài client trên máy B — bản portable test thì trỏ vào thư mục `Release\`)
- `--install-idd`: cài/cập nhật driver màn hình ảo (yêu cầu quyền admin — khuyến nghị dùng bản cài đặt DeskAgent có service chạy SYSTEM trên máy B; bản chạy bằng user thường sẽ không đủ quyền cài driver).
- `QRes.exe`: công cụ portable **bên thứ ba, không kèm theo repo** — tự chuẩn bị sẵn trên máy B (ví dụ `C:\Tools\`) để đặt độ phân giải; bỏ phần này nếu chỉ cần bật màn hình ảo.
- Màn hình ảo mặc định được tạo với độ phân giải 1920×1080 @60Hz và được bật tự động trong phiên điều khiển khi máy headless, hoặc bật/tắt từ toolbar phiên (menu chọn màn hình → virtual display).

**Cách xác nhận đã OK:** job `success` ở console; trên máy B, Device Manager / Settings → Display xuất hiện monitor ảo; phiên điều khiển từ A thấy được màn hình ảo với độ phân giải đặt.

### 6.2. Tuning độ mượt phiên điều khiển

- DeskAgent đã tự đặt mặc định **codec-preference = `auto`** cho người dùng chưa từng chỉnh (client chọn codec phần cứng h264/h265 khi cả 2 máy hỗ trợ — lợi thế lớn nhất về độ trễ trên LAN). Mặc định này chỉ áp dụng khi bạn chưa tự đổi.
- Muốn chỉnh thêm: trong phiên điều khiển, mở **toolbar phiên → Display/Quality**: chỉnh Image quality, FPS, và bật/tắt codec. Trên LAN nên để quality cao + FPS 30–60 nếu băng thông cho phép.

**Cách xác nhận đã OK:** kéo chuột/di chuyển cửa sổ trên máy B từ máy A, hình ảnh không giật khung lớn; cú đúp phím hiển thị tức thì; không thấy log lỗi codec trong phiên.

---

## 7. Troubleshooting

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| **Máy B không thấy trong console** | 1. `DESKAGENT_MANAGER_URL` sai hoặc chưa set (client mặc định `127.0.0.1:8080` — tìm Manager trên chính máy B) <br> 2. Firewall máy A chặn 8080 <br> 3. Client id cũ không tự register lại | 1. `setx DESKAGENT_MANAGER_URL "http://<IP-A>:8080"` hoặc chạy từ cmd với `set`, rồi khởi động lại client. Kiểm tra biến hiệu lực trong cmd: `echo %DESKAGENT_MANAGER_URL%` <br> 2. `Test-NetConnection <IP-A> -Port 8080` từ máy B; soát rule mục 1.2 <br> 3. Xoá `%LOCALAPPDATA%\DeskAgent\manager_client_id` và khởi động lại client |
| **Không kết nối được ID server / không thấy ID máy B** | 1. Key sai (đã dán tên file thay vì nội dung `id_ed25519.pub`) <br> 2. Sai port (ID là 21116, relay là 21117) <br> 3. hbbs/hbbr chưa chạy hoặc bị firewall chặn 21115–21119 | 1. Dán lại toàn bộ nội dung file `.pub` <br> 2. Sửa lại ID/Relay server trong UI <br> 3. Chạy lại `run-server.cmd`, `Test-NetConnection <IP-A> -Port 21116` từ máy B |
| **Job không chạy / failed** | 1. `package_path` sai — đường dẫn được kiểm tra **trên máy B**, không phải máy A <br> 2. `package_url` không phải http/https hoặc không tải được <br> 3. Máy B offline (không poll) | 1. Đọc ô **Kết quả** của job ở console — lỗi dạng `package_path does not exist: ...` cho biết đúng đường dẫn bị chê; sửa thành đường dẫn có thật trên máy B <br> 2. Mở URL bằng trình duyệt trên máy B để kiểm tra <br> 3. Bật máy B/client lại; job `pending` sẽ được nhận trong ~30 giây |
| **Bot không trả lời** | 1. Thiếu 1 trong 3 biến `DESKAGENT_AI_URL/KEY/MODEL` → reply "chưa cấu hình AI" <br> 2. Host AI bị chặn SSRF (localhost/private) hoặc không nằm trong `DESKAGENT_AI_HOSTS` <br> 3. AI upstream lỗi | 1. Set đủ 3 biến rồi khởi động lại Manager; log phải ra `AI proxy enabled: ...` <br> 2. Dùng endpoint public, thêm đúng tên host (không port) vào allowlist <br> 3. Reply trả về `[AI error]` — kiểm tra key/model/quota với nhà cung cấp AI |
| **Chat trong app máy B báo không tới được Manager** | App chat trỏ hằng `127.0.0.1:8080` (chưa đọc `DESKAGENT_MANAGER_URL`) | Đây là hạn chế của bản build hiện tại — test hội thoại bằng REST tới `http://<IP-A>:8080` (mục 5.4); kết quả vẫn hiển thị ở console. Muốn chat qua app thì cần đổi hằng trong `deskagent_config.dart` và build lại |
| **Inventory/events không cập nhật** | Chu kỳ upload là 10 phút/lần | Chờ chu kỳ kế tiếp hoặc khởi động lại client (upload ngay ở tick đầu tiên) |

---

## 8. Cảnh báo bảo mật

- **Manager hiện KHÔNG có xác thực** — mọi endpoint (`/api/...`, console, tạo job, đọc inventory/events, chat) đều truy cập tự do bởi bất kỳ ai thấy được cổng 8080. **Tuyệt đối không** port-forward 8080 ra internet hay chạy Manager trên máy có IP public; chỉ chạy trong LAN hoặc qua VPN.
- Giới hạn firewall theo subnet nội bộ — tạo rule Manager với `remoteip` (thay `<SUBNET-LAN>` bằng dải thật, ví dụ `192.168.1.0/24`):
  ```bat
  netsh advfirewall firewall delete rule name="DeskAgent Manager TCP"
  netsh advfirewall firewall add rule name="DeskAgent Manager TCP" dir=in action=allow protocol=TCP localport=8080 remoteip=<SUBNET-LAN>
  ```
  Có thể áp cách tương tự cho 2 rule hbbs/hbbr nếu server chỉ phục vụ nội bộ.
  **Xác nhận:** từ 1 máy ngoài subnet (nếu có) `Test-NetConnection <IP-A> -Port 8080` phải thất bại; từ máy trong subnet phải thành công.
- Không có auth nên bất kỳ ai trong LAN cũng có thể: tạo hội thoại với bot, **tạo deploy job chạy lệnh trên các máy client**, đọc inventory/event của toàn bộ máy. Khi làm việc ngoài phạm vi test, tắt Manager và mở lại rule firewall.
- Deploy job thực thi lệnh trên máy client qua `cmd /C` với quyền của process client — chỉ tạo job từ console khi bạn là người quản trị; khoá vùng console (chỉ LAN/VPN) trước khi cho phép dùng tính năng này.

---

## Phụ lục: tham chiếu code (đối chiếu khi tài liệu này được soạn)

| Nội dung | Vị trí |
|---|---|
| Env `DESKAGENT_MANAGER_URL`, mặc định `http://127.0.0.1:8080`, tick 30s, inventory mỗi 10 phút, chạy job qua `cmd /C` | `DeskAgent\src\deskagent\deploy.rs:12-17`, `deploy.rs:144-157`, `deploy.rs:410-423` |
| Daemon 30s + mặc định codec `auto` | `DeskAgent\src\deskagent\mod.rs:18`, `mod.rs:27-35` |
| Manager bind + manager.db cạnh thư mục chạy + log AI | `DeskAgent\manager\src\main.rs:26`, `main.rs:41-46` |
| Env AI + SSRF guard + allowlist host | `DeskAgent\manager\src\ai.rs:13-16`, `ai.rs:70-150` |
| API client/conversation/admin, vòng đời job, reply "chưa cấu hình AI", claimed → bot skip, reply admin | `DeskAgent\manager\src\routes.rs:70-96`, `routes.rs:204-229`, `routes.rs:254-287`, `routes.rs:346-371` |
| 4 vùng console | `DeskAgent\manager\console\index.html:315-329` |
| System Info / Event Viewer / AI Chat trong app | `DeskAgent\flutter\lib\features\deskagent\deskagent_home_page.dart:24-45` |
| Chat app trỏ hằng `127.0.0.1:8080` | `DeskAgent\flutter\lib\features\deskagent\deskagent_config.dart:5` |
| `--install-idd` cài màn hình ảo; màn ảo 1920×1080@60 | `DeskAgent\src\core_main.rs:294-301`, `DeskAgent\src\virtual_display_manager.rs:202-211` |
| Tên exe client `rustdesk.exe` | `DeskAgent\flutter\windows\CMakeLists.txt:7`, `build.py:976` |
