#!/usr/bin/env bash
set -Eeuo pipefail

# Always leave the alt screen / sane TTY on exit
reset_tty() {
  { command -v tput >/dev/null 2>&1 && tput rmcup; } || printf '\e[?1049l'
  stty sane 2>/dev/null || true
}
trap reset_tty EXIT

# ========================= Colors & UI helpers =========================
init_colors() {
  if [ -n "${FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; }; then
    if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
      RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; BOLD="$(tput bold)"; RESET="$(tput sgr0)"
    else
      RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
    fi
  else
    RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
  fi
}
init_colors

rule()        { printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
hdr()         { printf '\n'; rule; printf " %s%s%s \n" "$BOLD" "$*" "$RESET"; rule; }
say()         { printf "▶ %s\n" "$*"; }
say_inline()  { printf "▶ %s " "$*"; }                 # no newline
ok()          { printf "%b✓%b %s\n" "$GREEN" "$RESET" "$*"; }
warn()        { printf "%b⚠%b %s\n" "$YELLOW" "$RESET" "$*"; }
warn_inline() { printf "%b⚠%b %s\n" "$YELLOW" "$RESET" "$*"; }
die()         { printf "%b❌%b %s\n" "$RED" "$RESET" "$*"; exit 1; }

# ============================ Config =============================
WORKDIR="/workspace"
COMFY_DIR="${WORKDIR}/ComfyUI"
CONDA_SH="${WORKDIR}/miniconda3/etc/profile.d/conda.sh"
CONDA_ENV="comfyui"
PORT=8188

# ============================ Finish banner =============================
print_finish_banner() {
  rule
  printf "All set! Launch ComfyUI with:\n"
  printf "  python main.py --fast --listen --disable-cuda-malloc\n\n"
  printf "                               Check out my other tools on GitHub:\n"
  printf "                               https://github.com/CryptoAce85\n\n"
  printf "                               Made with 💖  by 🐺  CryptoAce85 🐺\n\n"
  printf '%b' "$GREEN"
  cat <<'ASCII'
           ░█▀█░█░░░█░░░░░█▀▄░█▀█░█▀█░█▀▀░█░░░█▀▀░▀█▀░█▀█░█▀▄░▀█▀░░░█▀▀░█▀█░█▄█░█▀▀░█░█░░░█░█░▀█▀░░░
           ░█▀█░█░░░█░░░░░█░█░█░█░█░█░█▀▀░▀░░░▀▀█░░█░░█▀█░█▀▄░░█░░░░█░░░█░█░█░█░█▀▀░░█░░░░█░█░░█░░░░
           ░▀░▀░▀▀▀░▀▀▀░░░▀▀░░▀▀▀░▀░▀░▀▀▀░▀░░░▀▀▀░░▀░░▀░▀░▀░▀░░▀░░░░▀▀▀░▀▀▀░▀░▀░▀░░░░▀░░░░▀▀▀░▀▀▀░▀░
ASCII
  printf '%b' "$RESET"
}

# ============================ Steps =============================
check_system_deps() {
  hdr "ComfyUI Post-Start Fixes"
  hdr "Checking system dependencies…"
  if [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
    SUDO=""; [ "$EUID" -ne 0 ] && SUDO="sudo"
    $SUDO ldconfig >/dev/null 2>&1 || true
    if command -v apt >/dev/null 2>&1; then
      if ! dpkg -l 2>/dev/null | grep -q unzip; then
        $SUDO apt update -qq || true
        $SUDO apt install -y unzip >/dev/null 2>&1 || true
      fi
    fi
  fi
  ok "System deps checked."
}

clean_caches() {
  hdr "Cleaning caches and pyc files…"
  rm -rf "${COMFY_DIR}/custom_nodes/.cache" 2>/dev/null || true
  find "${COMFY_DIR}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  find "${COMFY_DIR}" -name "*.pyc" -delete 2>/dev/null || true
  rm -rf ~/.triton/cache /tmp/latentsync_* 2>/dev/null || true
  mkdir -p ~/.triton/cache
  ok "Caches cleaned."
}

activate_env() {
  hdr "Activating Conda environment: ${CONDA_ENV}"
  [ -f "${CONDA_SH}" ] || die "Conda not found at ${CONDA_SH}"
  # shellcheck disable=SC1090
  source "${CONDA_SH}"
  conda activate "${CONDA_ENV}" || die "Failed to activate ${CONDA_ENV}"
  PYBIN="$(command -v python)"
  case "$PYBIN" in *"/envs/${CONDA_ENV}/"*) : ;; *) die "Conda activation failed; python is ${PYBIN}";; esac
  ok "Conda environment: ${CONDA_ENV}"
}

set_runtime_env() {
  hdr "Setting runtime environment…"
  export TORCH_DISABLE_SAFE_DESERIALIZER=1
  export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
  export TOKENIZERS_PARALLELISM=false
  export BITSANDBYTES_NOWELCOME=1
  export TRITON_CACHE_DIR=/tmp/triton_cache
  mkdir -p /tmp/triton_cache
  ok "Environment variables set."
}

sanitize_custom_nodes() {
  hdr "Removing stray/bogus custom_nodes that cause import errors…"
  for bad in "ComfyUI" "stable-diffusion-webui"; do
    if [ -d "${COMFY_DIR}/custom_nodes/${bad}" ]; then
      warn "Found custom_nodes/${bad} — removing."
      rm -rf "${COMFY_DIR}/custom_nodes/${bad}" || true
    fi
  done
  if [ -d "${COMFY_DIR}/custom_nodes/ComfyUI_Various" ] && [ ! -f "${COMFY_DIR}/custom_nodes/ComfyUI_Various/__init__.py" ]; then
    warn "Found custom_nodes/ComfyUI_Various without __init__.py — removing."
    rm -rf "${COMFY_DIR}/custom_nodes/ComfyUI_Various" || true
  fi
  ok "Custom-node folder sanity pass complete."
}

ensure_optional_node_deps() {
  hdr "Ensuring optional node dependencies…"

  # comfyui_faceanalysis -> insightface
  if [ -d "${COMFY_DIR}/custom_nodes/comfyui_faceanalysis" ]; then
    say "comfyui_faceanalysis present — checking for insightface…"
    if ! python - <<'PY' >/dev/null 2>&1
try:
  import insightface  # noqa
except Exception:
  raise SystemExit(1)
PY
    then
      pip install --no-cache-dir insightface >/dev/null 2>&1 || warn "insightface install failed"
    else
      ok "insightface already installed."
    fi
  fi

  # ControlNet Aux -> onnxruntime
  if [ -d "${COMFY_DIR}/custom_nodes/comfyui_controlnet_aux" ]; then
    if ! python -c "import onnxruntime" >/dev/null 2>&1; then
      pip install --no-cache-dir onnxruntime >/dev/null 2>&1 || warn "onnxruntime install failed"
    fi
  fi

  # LayerStyle needs cv2.ximgproc (opencv-contrib-python)
  if [ -d "${COMFY_DIR}/custom_nodes/ComfyUI_LayerStyle" ] || [ -d "${COMFY_DIR}/custom_nodes/ComfyUI_LayerStyle_Advance" ]; then
    python - <<'PY' >/dev/null 2>&1 || pip install --no-cache-dir opencv-contrib-python >/dev/null 2>&1 || true
import cv2, sys
ok = True
try:
  from cv2 import ximgproc  # type: ignore
  _ = ximgproc.guidedFilter
except Exception:
  ok = False
sys.exit(0 if ok else 1)
PY
  fi

  # Core import needs torchsde in new Comfy versions
  if ! python -c "import torchsde" >/dev/null 2>&1; then
    pip install --no-cache-dir torchsde >/dev/null 2>&1 || warn "torchsde install failed"
  fi

  ok "Node dependency check complete."
}

free_port() {
  rule
  say_inline "Ensuring port ${PORT} is free…"
  local PIDS=""
  if command -v ss >/dev/null 2>&1; then
    PIDS="$(ss -ltnp 2>/dev/null | awk -v p=":${PORT} " '$0 ~ p {print $7}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | xargs -r echo)"
  else
    PIDS="$(lsof -ti :"${PORT}" 2>/dev/null | xargs -r echo || true)"
  fi

  if [ -n "${PIDS:-}" ]; then
    warn_inline "Port ${PORT} is busy; attempting to stop: ${PIDS}"
    for pid in $PIDS; do kill -TERM "$pid" 2>/dev/null || true; done
    sleep 2
    if command -v ss >/dev/null 2>&1; then
      PIDS2="$(ss -ltnp 2>/dev/null | awk -v p=":${PORT} " '$0 ~ p {print $7}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | xargs -r echo)"
    else
      PIDS2="$(lsof -ti :"${PORT}" 2>/dev/null | xargs -r echo || true)"
    fi
    if [ -n "${PIDS2:-}" ]; then
      for pid in $PIDS2; do kill -KILL "$pid" 2>/dev/null || true; done
      sleep 1
    fi
    ok "Port ${PORT} freed."
  else
    ok "Port ${PORT} is free."
  fi
}

start_comfyui() {
  rule
  say "Starting ComfyUI on port ${PORT}…"
  cd "${COMFY_DIR}"

  STDBUF=""
  command -v stdbuf >/dev/null 2>&1 && STDBUF="stdbuf -oL -eL"

  # Stream logs; print finish banner right when Manager reports completion
  PYTHONUNBUFFERED=1 ${STDBUF} python -u main.py --fast --listen --disable-cuda-malloc 2>&1 \
  | while IFS= read -r line; do
      echo "${line}"
      if [[ "${line}" == *"All startup tasks have been completed."* ]]; then
        print_finish_banner
      fi
    done
}

# ============================ Main =============================
main() {
  check_system_deps
  clean_caches
  activate_env
  set_runtime_env
  sanitize_custom_nodes
  ensure_optional_node_deps
  free_port
  start_comfyui
}

main
sleep 0.1
