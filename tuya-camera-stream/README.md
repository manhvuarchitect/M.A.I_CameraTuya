# M.A.I Tuya Camera Stream

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Arch](https://img.shields.io/badge/arch-amd64%20|%20aarch64%20|%20armv7-green)

Stream camera **Tuya Smart / Smart Life** trực tiếp vào Home Assistant qua RTSP local — không cần WebRTC, không cần cloud relay.

## Cách hoạt động

```
Camera Tuya
    ↓ (Tuya P2P / WebRTC protocol)
tuya-ipc-terminal  ← addon này
    ↓ RTSP :8554 (local network)
Home Assistant Generic Camera / go2rtc
    ↓
Dashboard
```

Addon sử dụng [tuya-ipc-terminal](https://github.com/seydx/tuya-ipc-terminal) — reverse-engineered Tuya web client API — để tạo WebRTC-to-RTSP bridge chạy hoàn toàn local.

---

## Cài đặt

### Bước 1: Thêm repository

Trong Home Assistant:
**Settings → Add-ons → Add-on Store → ⋮ → Repositories**

Thêm URL:
```
https://github.com/manhvuarchitect/M.A.I-addons
```

### Bước 2: Cài addon

Tìm **"M.A.I Tuya Camera Stream"** → Install.

### Bước 3: Cấu hình

| Option | Mô tả | Gợi ý |
|--------|-------|-------|
| `region` | Region tài khoản Tuya | VN → thử `eu-central` trước, nếu lỗi thử `china` |
| `email` | Email đăng nhập | Email dùng trong Tuya/Smart Life app |
| `auth_method` | Cách đăng nhập | `qr` = tiện nhất |
| `rtsp_port` | Port RTSP | Mặc định `8554` |
| `log_level` | Mức log | `info` bình thường, `debug` khi troubleshoot |

### Bước 4: Đăng nhập lần đầu (QR method)

1. **Start** addon
2. Mở tab **Log**
3. Chờ QR code xuất hiện trong log
4. Mở **Tuya Smart** hoặc **Smart Life** app trên điện thoại
5. Vào **Profile → Scan** → scan QR
6. Addon tự động detect session và khởi động RTSP server

> Session được lưu trong `/data/tuya-ipc/` — không cần đăng nhập lại sau khi restart.

---

## Thêm camera vào Home Assistant

### Option A: Generic Camera (đơn giản)

```yaml
# configuration.yaml
camera:
  - platform: generic
    name: "Camera Cửa Trước"
    stream_source: "rtsp://homeassistant.local:8554/TenCamera"
    verify_ssl: false
```

Tên camera lấy từ **Log** của addon (xuất hiện sau khi discover).

### Option B: go2rtc (low-latency, recommended)

```yaml
# /config/go2rtc.yaml
streams:
  camera_cua_truoc:
    - rtsp://localhost:8554/TenCamera
  camera_san_nha:
    - rtsp://localhost:8554/TenCamera2
```

Sau đó dùng **WebRTC Camera** card của AlexxIT:
```yaml
type: custom:webrtc-camera
entity: camera.camera_cua_truoc
```

### Sub-stream (chất lượng thấp hơn, ít bandwidth)

```
rtsp://homeassistant.local:8554/TenCamera/sd
```

---

## Troubleshoot

### Không tìm thấy camera
```
# Xem log để lấy danh sách camera đã discover
# Tên camera trong URL phân biệt hoa thường
```

### Session hết hạn
Addon tự động refresh session. Nếu vẫn lỗi → **Restart addon** → scan QR lại.

### Region sai
Camera VN mua từ Lazada/Shopee thường link tài khoản vào:
- `eu-central` (nếu app hiển thị flag EU)  
- `china` (nếu tài khoản tạo bằng số điện thoại VN trong app Trung Quốc)

Thử lần lượt cả hai.

### Port 8554 bị conflict
Đổi `rtsp_port` sang `8555` hoặc `8556`.

---

## Tương thích

| Model | Kết quả |
|-------|---------|
| `sp` (Smart cameras) | ✅ Full support |
| `dghsxj` | ✅ Full support |
| Các model Tuya khác | ⚠️ Có thể hoạt động |

Camera hỗ trợ ONVIF → có thể dùng ONVIF trực tiếp thay addon này (local, không cần cloud).

---

## License

MIT — xem [LICENSE](LICENSE)

> Dự án này thuộc hệ sinh thái **M.A.I Smart Home** bởi [@manhvuarchitect](https://github.com/manhvuarchitect)
