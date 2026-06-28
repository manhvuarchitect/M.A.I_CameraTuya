#!/usr/bin/with-contenv bashio

REGION=$(bashio::config 'region')
EMAIL=$(bashio::config 'email')
AUTH_METHOD=$(bashio::config 'auth_method')
RTSP_PORT=$(bashio::config 'rtsp_port')
LOG_LEVEL=$(bashio::config 'log_level')

BINARY="/usr/bin/tuya-ipc-terminal"
DATA_DIR="/data/tuya-ipc"

# tuya-ipc-terminal lưu data tại $HOME/.tuya-data
# Override HOME để data persist vào /data qua restart
export HOME="${DATA_DIR}"
mkdir -p "${DATA_DIR}/.tuya-data"

bashio::log.info "════════════════════════════════════════"
bashio::log.info "  M.A.I Tuya Camera Stream Addon"
bashio::log.info "  Region : ${REGION}"
bashio::log.info "  Email  : ${EMAIL}"
bashio::log.info "  Port   : ${RTSP_PORT}"
bashio::log.info "════════════════════════════════════════"

if bashio::var.is_empty "${EMAIL}"; then
    bashio::log.fatal "Email chưa được cấu hình! Vào Configuration để nhập email."
    exit 1
fi

# ─── Tên session file theo convention của tuya-ipc-terminal ───────────────────
SESSION_KEY="${REGION}_$(echo ${EMAIL} | sed 's/@/_at_/' | tr '.' '_')"
SESSION_FILE="${DATA_DIR}/.tuya-data/user_${SESSION_KEY}.json"

# ─── Kiểm tra session hiện có ─────────────────────────────────────────────────
if [ -f "${SESSION_FILE}" ]; then
    bashio::log.info "Tìm thấy session, đang kiểm tra..."
    if ${BINARY} auth test "${REGION}" "${EMAIL}" 2>/dev/null; then
        bashio::log.info "✓ Session hợp lệ, bỏ qua đăng nhập"
    else
        bashio::log.warning "Session hết hạn → xoá và đăng nhập lại"
        rm -f "${SESSION_FILE}"
    fi
fi

# ─── Đăng nhập lần đầu ────────────────────────────────────────────────────────
if [ ! -f "${SESSION_FILE}" ]; then
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bashio::log.info "ĐĂNG NHẬP LẦN ĐẦU"
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "${AUTH_METHOD}" = "qr" ]; then
        bashio::log.info "QR code sẽ xuất hiện bên dưới."
        bashio::log.info "Bạn có 120 giây để scan bằng Tuya Smart / Smart Life app."
        bashio::log.info "Sau khi scan xong, addon tự động tiếp tục."
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Dùng expect để tương tác đúng với binary
        expect -c "
            log_user 1
            set timeout 120
            spawn ${BINARY} auth add ${REGION} ${EMAIL} --qr
            expect {
                \"Press Enter after scanning\" {
                    # Đã scan xong, gửi Enter
                    send \"\r\"
                    exp_continue
                }
                \"successfully\" {
                    # Login OK
                }
                \"Error\" {
                    exit 1
                }
                timeout {
                    send \"\r\"
                }
                eof {}
            }
        " 2>&1 | while IFS= read -r line; do
            bashio::log.info "${line}"
        done

        # Kiểm tra session đã tạo chưa
        if [ ! -f "${SESSION_FILE}" ]; then
            bashio::log.error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            bashio::log.error "Đăng nhập thất bại! Nguyên nhân có thể:"
            bashio::log.error "  1. Chưa scan QR trong 120 giây"
            bashio::log.error "  2. Region sai — VN thử 'china' thay vì 'eu-central'"
            bashio::log.error "  3. Email/tài khoản không đúng"
            bashio::log.error "→ Đổi region trong Configuration rồi Restart addon."
            bashio::log.error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 1
        fi

        bashio::log.info "✓ Đăng nhập thành công!"

    else
        # Password method
        bashio::log.info "Auth method = password"
        bashio::log.info "Vào HA Terminal (SSH addon) và chạy:"
        bashio::log.info ""
        bashio::log.info "  docker exec -it \$(docker ps --format '{{.Names}}' | grep mai_tuya) bash"
        bashio::log.info "  HOME=/data/tuya-ipc /usr/bin/tuya-ipc-terminal auth add --password ${REGION} ${EMAIL}"
        bashio::log.info ""
        bashio::log.info "Sau khi đăng nhập xong → Restart addon."
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        WAIT=0
        while [ ! -f "${SESSION_FILE}" ]; do
            sleep 10
            WAIT=$((WAIT + 10))
            if [ $((WAIT % 60)) -eq 0 ]; then
                bashio::log.info "Vẫn đang chờ đăng nhập... (${WAIT}s)"
            fi
        done
        bashio::log.info "✓ Session detected, tiếp tục khởi động..."
    fi
fi

# ─── Discover cameras ─────────────────────────────────────────────────────────
bashio::log.info "Đang tìm camera Tuya..."
${BINARY} cameras refresh 2>&1 | while IFS= read -r line; do
    bashio::log.info "[discover] ${line}"
done

bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bashio::log.info "DANH SÁCH CAMERA:"
${BINARY} cameras list 2>&1 | while IFS= read -r line; do
    bashio::log.info "  📷 ${line}"
done
bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Hướng dẫn thêm vào HA ────────────────────────────────────────────────────
bashio::log.info "Thêm camera vào Home Assistant:"
bashio::log.info "  camera:"
bashio::log.info "    - platform: generic"
bashio::log.info "      stream_source: rtsp://homeassistant.local:${RTSP_PORT}/[TenCamera]"
bashio::log.info "      name: My Camera"
bashio::log.info ""
bashio::log.info "Hoặc trong go2rtc.yaml:"
bashio::log.info "  streams:"
bashio::log.info "    camera_tuya:"
bashio::log.info "      - rtsp://localhost:${RTSP_PORT}/[TenCamera]"
bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Start RTSP server ────────────────────────────────────────────────────────
bashio::log.info "Khởi động RTSP server trên port ${RTSP_PORT}..."

exec ${BINARY} rtsp start --port "${RTSP_PORT}" 2>&1 | while IFS= read -r line; do
    bashio::log.info "[rtsp] ${line}"
done
