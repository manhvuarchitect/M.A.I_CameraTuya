#!/usr/bin/with-contenv bashio

# ─── Read options from HA addon config ────────────────────────────────────────
REGION=$(bashio::config 'region')
EMAIL=$(bashio::config 'email')
AUTH_METHOD=$(bashio::config 'auth_method')
RTSP_PORT=$(bashio::config 'rtsp_port')
LOG_LEVEL=$(bashio::config 'log_level')

DATA_DIR="/data/tuya-ipc"
BINARY="/usr/bin/tuya-ipc-terminal"

bashio::log.info "════════════════════════════════════════"
bashio::log.info "  M.A.I Tuya Camera Stream Addon"
bashio::log.info "  Region : ${REGION}"
bashio::log.info "  Email  : ${EMAIL}"
bashio::log.info "  Port   : ${RTSP_PORT}"
bashio::log.info "════════════════════════════════════════"

# ─── Validate config ──────────────────────────────────────────────────────────
if bashio::var.is_empty "${EMAIL}"; then
    bashio::log.fatal "Email chưa được cấu hình! Vào Addon Configuration để nhập email Tuya/Smart Life."
    exit 1
fi

# ─── Prepare data directory (persisted in /data) ─────────────────────────────
mkdir -p "${DATA_DIR}"
export TUYA_DATA_DIR="${DATA_DIR}"

# ─── Check if already authenticated ──────────────────────────────────────────
SESSION_FILE="${DATA_DIR}/user_${REGION}_$(echo ${EMAIL} | tr '@.' '_').json"

if [ -f "${SESSION_FILE}" ]; then
    bashio::log.info "Session file found, kiểm tra tính hợp lệ..."
    
    # Test session validity
    if ${BINARY} auth test "${REGION}" "${EMAIL}" --data-dir "${DATA_DIR}" 2>/dev/null; then
        bashio::log.info "✓ Session hợp lệ, bỏ qua bước đăng nhập"
    else
        bashio::log.warning "Session đã hết hạn, đang refresh..."
        ${BINARY} auth refresh "${REGION}" "${EMAIL}" --data-dir "${DATA_DIR}" || {
            bashio::log.warning "Refresh thất bại. Xoá session cũ, cần đăng nhập lại."
            rm -f "${SESSION_FILE}"
        }
    fi
fi

# ─── First-time authentication ────────────────────────────────────────────────
if [ ! -f "${SESSION_FILE}" ]; then
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bashio::log.info "HƯỚNG DẪN ĐĂNG NHẬP LẦN ĐẦU:"
    bashio::log.info ""
    
    if [ "${AUTH_METHOD}" = "qr" ]; then
        bashio::log.info "1. Mở Log của addon này"
        bashio::log.info "2. Mở app Tuya Smart hoặc Smart Life trên điện thoại"
        bashio::log.info "3. Scan QR code xuất hiện trong log"
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        ${BINARY} auth add "${REGION}" "${EMAIL}" \
            --data-dir "${DATA_DIR}" \
            --non-interactive 2>&1 | while IFS= read -r line; do
            bashio::log.info "${line}"
        done
    else
        bashio::log.info "Auth method = password. Dùng HA Terminal để chạy lệnh sau:"
        bashio::log.info ""
        bashio::log.info "  docker exec \$(docker ps -q -f name=mai_tuya_camera) \\"
        bashio::log.info "    /usr/bin/tuya-ipc-terminal auth add ${REGION} ${EMAIL} \\"
        bashio::log.info "    --password --data-dir /data/tuya-ipc"
        bashio::log.info ""
        bashio::log.info "Sau khi đăng nhập xong, restart addon."
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Wait for manual auth
        while [ ! -f "${SESSION_FILE}" ]; do
            bashio::log.info "Chờ đăng nhập... (kiểm tra mỗi 15 giây)"
            sleep 15
        done
        bashio::log.info "✓ Phát hiện session file, tiếp tục khởi động..."
    fi
fi

# ─── Discover / refresh cameras ───────────────────────────────────────────────
bashio::log.info "Đang tìm camera Tuya..."
${BINARY} cameras refresh --data-dir "${DATA_DIR}" 2>&1 | while IFS= read -r line; do
    bashio::log.info "[cameras] ${line}"
done

# List discovered cameras
bashio::log.info "━━━━━ Danh sách camera ━━━━━"
${BINARY} cameras list --data-dir "${DATA_DIR}" 2>&1 | while IFS= read -r line; do
    bashio::log.info "  ${line}"
done
bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Start RTSP server ────────────────────────────────────────────────────────
bashio::log.info "Khởi động RTSP server trên port ${RTSP_PORT}..."
bashio::log.info ""
bashio::log.info "Thêm camera vào Home Assistant:"
bashio::log.info "  stream_source: rtsp://homeassistant.local:${RTSP_PORT}/[TenCamera]"
bashio::log.info ""

exec ${BINARY} rtsp start \
    --port "${RTSP_PORT}" \
    --data-dir "${DATA_DIR}" \
    --log-level "${LOG_LEVEL}" \
    2>&1 | while IFS= read -r line; do
    bashio::log.info "[rtsp] ${line}"
done
