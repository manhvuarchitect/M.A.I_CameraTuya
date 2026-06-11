#!/usr/bin/with-contenv bashio

REGION=$(bashio::config 'region')
EMAIL=$(bashio::config 'email')
AUTH_METHOD=$(bashio::config 'auth_method')
RTSP_PORT=$(bashio::config 'rtsp_port')
LOG_LEVEL=$(bashio::config 'log_level')

BINARY="/usr/bin/tuya-ipc-terminal"
DATA_DIR="/data/tuya-ipc"

# tuya-ipc-terminal lưu data tại $HOME/.tuya-data
# Ta override HOME để data persist vào /data
export HOME="${DATA_DIR}"
mkdir -p "${DATA_DIR}/.tuya-data"

bashio::log.info "════════════════════════════════════════"
bashio::log.info "  M.A.I Tuya Camera Stream Addon"
bashio::log.info "  Region : ${REGION}"
bashio::log.info "  Email  : ${EMAIL}"
bashio::log.info "  Port   : ${RTSP_PORT}"
bashio::log.info "════════════════════════════════════════"

if bashio::var.is_empty "${EMAIL}"; then
    bashio::log.fatal "Email chưa được cấu hình!"
    exit 1
fi

# ─── Check session ────────────────────────────────────────────────────────────
SESSION_FILE="${DATA_DIR}/.tuya-data/user_${REGION}_$(echo ${EMAIL} | tr '@.' '_').json"

if [ -f "${SESSION_FILE}" ]; then
    bashio::log.info "Session file found, kiểm tra tính hợp lệ..."
    if ${BINARY} auth test "${REGION}" "${EMAIL}" 2>/dev/null; then
        bashio::log.info "✓ Session hợp lệ"
    else
        bashio::log.warning "Session hết hạn, xoá và đăng nhập lại..."
        rm -f "${SESSION_FILE}"
    fi
fi

# ─── First-time auth ──────────────────────────────────────────────────────────
if [ ! -f "${SESSION_FILE}" ]; then
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bashio::log.info "ĐĂNG NHẬP LẦN ĐẦU:"

    if [ "${AUTH_METHOD}" = "qr" ]; then
        bashio::log.info "Mở app Tuya Smart / Smart Life → Profile → Scan QR bên dưới:"
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Chạy auth trong nền, forward output vào log
        ${BINARY} auth add "${REGION}" "${EMAIL}" --qr 2>&1 | while IFS= read -r line; do
            bashio::log.info "${line}"
        done

    else
        bashio::log.info "Auth method = password"
        bashio::log.info "Vào HA Terminal và chạy:"
        bashio::log.info "  docker exec -it \$(docker ps -q -f name=mai_tuya_camera) /bin/bash"
        bashio::log.info "  HOME=/data/tuya-ipc tuya-ipc-terminal auth add --password ${REGION} ${EMAIL}"
        bashio::log.info "Sau khi đăng nhập xong, restart addon."
        bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        while [ ! -f "${SESSION_FILE}" ]; do
            sleep 10
        done
        bashio::log.info "✓ Session detected, tiếp tục..."
    fi
fi

# ─── Discover cameras ─────────────────────────────────────────────────────────
bashio::log.info "Đang tìm camera..."
${BINARY} cameras refresh 2>&1 | while IFS= read -r line; do
    bashio::log.info "[cameras] ${line}"
done

bashio::log.info "━━━━━━━ Danh sách camera ━━━━━━━"
${BINARY} cameras list 2>&1 | while IFS= read -r line; do
    bashio::log.info "  ${line}"
done
bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Start RTSP server ────────────────────────────────────────────────────────
bashio::log.info "Khởi động RTSP server :${RTSP_PORT}..."
bashio::log.info "stream_source: rtsp://homeassistant.local:${RTSP_PORT}/[TenCamera]"

exec ${BINARY} rtsp start --port "${RTSP_PORT}" 2>&1 | while IFS= read -r line; do
    bashio::log.info "[rtsp] ${line}"
done
