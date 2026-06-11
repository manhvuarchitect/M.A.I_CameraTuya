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
SESSION_KEY="${REGION}_$(echo ${EMAIL} | tr '@.' '_')"
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
        bashio::log.info "Bạn có 90 giây để scan bằng Tuya Smart / Smart Life app."
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Gửi Enter tự động sau 90 giây để tiếp tục sau khi scan
        (sleep 90 && echo "") | ${BINARY} auth add "${REGION}" "${EMAIL}" --qr 2>&1 | \
            while IFS= read -r line; do
                bashio::log.info "${line}"
            done

        # Kiểm tra session đã tạo chưa
        if [ ! -f "${SESSION_FILE}" ]; then
            bashio::log.error "Đăng nhập thất bại! Có thể do:"
            bashio::log.error "  1. Chưa scan QR trong 90 giây"
            bashio::log.error "  2. Region sai (VN thử 'eu-central' hoặc 'china')"
            bashio::log.error "  3. Tài khoản không hợp lệ"
            bashio::log.error "Restart addon để thử lại."
            exit 1
        fi

        bashio::log.info "✓ Đăng nhập thành công!"

    else
        # Password method — cần tương tác qua terminal
        bashio::log.info "Auth method = password"
        bashio::log.info "Vào HA Terminal (SSH addon) và chạy lệnh sau:"
        bashio::log.info ""
        bashio::log.info "  docker exec -it \$(docker ps --format '{{.Names}}' | grep mai_tuya) bash"
        bashio::log.info "  HOME=/data/tuya-ipc /usr/bin/tuya-ipc-terminal auth add --password ${REGION} ${EMAIL}"
        bashio::log.info ""
        bashio::log.info "Sau khi đăng nhập xong → Restart addon này."
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Chờ session file xuất hiện
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
bashio::log.info "      name: \"Camera Tuya\""
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
