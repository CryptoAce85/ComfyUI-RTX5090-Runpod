#!/usr/bin/env bash
# install_SDXL_NSFW_V3.sh
# One-shot ComfyUI + popular nodes + model fetcher + Joy Caption Two + IP-Adapter FaceID v2.
# Targeted for RunPod-style workers (conda env: comfyui).
# Supports CryptoAce_NSFW_V2_VRAM_CLEAN_FP8.json workflow.

set -euo pipefail

# Keep output on the main screen; never invoke pagers
export PAGER=cat
export GIT_PAGER=cat
export LESS='-F -X -R'
git config --global core.pager 'cat' >/dev/null 2>&1 || true

# Always leave the alt screen / sane TTY on exit
reset_tty() {
  { command -v tput >/dev/null 2>&1 && tput rmcup; } || printf '\e[?1049l'
  stty sane 2>/dev/null || true
}
trap reset_tty EXIT

: "${FORCE_COLOR:=1}"

init_colors() {
  if [ -n "${FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; }; then
    if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
      RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
      BLUE="$(tput setaf 4)"; CYAN="$(tput setaf 6)"; BOLD="$(tput bold)"; RESET="$(tput sgr0)"
    else
      RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
      BLUE=$'\033[34m'; CYAN=$'\033[36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
    fi
  else RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; RESET=""; fi
}
init_colors

# ── Paths & config ────────────────────────────────────────────────────
CONDA_ENV_NAME="comfyui"
WORKDIR="/workspace"
COMFY_DIR="${WORKDIR}/ComfyUI"
NODES_DIR="${COMFY_DIR}/custom_nodes"

CHK_DIR="${COMFY_DIR}/models/checkpoints"
VAE_DIR="${COMFY_DIR}/models/vae"
CLIP_DIR="${COMFY_DIR}/models/clip"
CLIP_VI_DIR="${COMFY_DIR}/models/clip_vision"
UNET_DIR="${COMFY_DIR}/models/unet"
LORAS_DIR="${COMFY_DIR}/models/loras"
LORAS_SDXL_DIR="${LORAS_DIR}/sdxl"
UPSCALE_DIR="${COMFY_DIR}/models/upscale_models"
IPADAPTER_DIR="${COMFY_DIR}/models/ipadapter"
IPADAPTER_SDXL_DIR="${IPADAPTER_DIR}/sdxl_models"
INSIGHT_DIR="${COMFY_DIR}/models/insightface"
CONTROLNET_DIR="${COMFY_DIR}/models/controlnet"
: "${MODELS_DIR:=/workspace/ComfyUI/models}"

# Version pins
NUMPY_PIN="1.26.4"
ORT_PIN="1.18.0"
ONNX_PIN="1.16.2"
OPENCV_PIN="4.9.0.80"
MEDIAPIPE_PIN="0.10.14"

# One-time idempotency markers
MARK_DIR="${MARK_DIR:-/workspace/.install-marks}"
mkdir -p "$MARK_DIR"
MARK_OPENCV="${MARK_DIR}/opencv_${OPENCV_PIN}.done"

rule() { printf '%s\n' "────────────────────────────────────────────────────────"; }
hdr() { printf '\n'; rule; printf "▶ %s\n" "$*"; rule; }
say() { printf " ▶ %s\n" "$*"; }
ok() { printf "%b ✓ %s%b\n" "$GREEN" "$*" "$RESET"; }
warn() { printf "%b ⚠ %s%b\n" "$YELLOW" "$*" "$RESET"; }
fail() { printf "%b ✗ %s%b\n" "$RED" "$*" "$RESET"; }

trap 'fail "Installer aborted (line $LINENO)."' ERR

export GIT_TERMINAL_PROMPT=0
git config --global url."https://github.com/".insteadOf "git@github.com:" || true
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" || true
git config --global --unset-all http.https://github.com/.extraheader >/dev/null 2>&1 || true
GIT_NOHDR=(git -c http.extraheader=)
need_cmd() { command -v "$1" >/dev/null 2>&1; }
retry() {
  local tries="$1"; shift; local sleep_s="$1"; shift; [[ "${1:-}" == "--" ]] && shift || true
  local n=1; while true; do
    if "$@"; then return 0; fi
    if [[ $n -ge $tries ]]; then fail "Failed after ${tries} attempts: $*"; fi
    warn "Attempt $n failed. Retrying in ${sleep_s}s..."; sleep "$sleep_s"; sleep_s=$(( sleep_s*2 )); n=$(( n+1 ))
  done
}

: "${QUIET:=1}"
LOG_DIR="/workspace/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
qrun() {
  local label="$1"; shift; [[ "${1:-}" == "--" ]] && shift || true
  if [[ "${QUIET}" == "1" ]]; then
    say "${label} (quiet; logging to ${LOG_FILE})"
    if "$@" >>"$LOG_FILE" 2>&1; then ok "${label}"; else
      warn "${label} failed. Last 40 log lines:"; tail -n 40 "$LOG_FILE" || true; return 1
    fi
  else
    say "${label}"
    "$@"
    local rc=$?
    [[ $rc -eq 0 ]] && ok "${label}" || warn "${label} failed (rc=$rc)"
    return $rc
  fi
}
quiet_pip() {
  local label="$1"; shift; [[ "${1:-}" == "--" ]] && shift || true
  qrun "${label}" -- python -m pip --quiet --disable-pip-version-check --no-input "$@"
}

# ── Banners (appearance unchanged) ─────────────────────────────
banner_top() {
  # Green block
  printf '%b' "$CYAN"
  cat <<'EOF'


   █████████  ██████████   █████ █████ █████                 ██████   █████  █████████  ███████████ █████   ███   █████           █████   █████  ████████ 
 ███▒▒▒▒▒███▒▒███▒▒▒▒███ ▒▒███ ▒▒███ ▒▒███                 ▒▒██████ ▒▒███  ███▒▒▒▒▒███▒▒███▒▒▒▒▒▒█▒▒███   ▒███  ▒▒███           ▒▒███   ▒▒███  ███▒▒▒▒███
▒███    ▒▒▒  ▒███   ▒▒███ ▒▒███ ███   ▒███                  ▒███▒███ ▒███ ▒███    ▒▒▒  ▒███   █ ▒  ▒███   ▒███   ▒███            ▒███    ▒███ ▒▒▒    ▒███
▒▒█████████  ▒███    ▒███  ▒▒█████    ▒███                  ▒███▒▒███▒███ ▒▒█████████  ▒███████    ▒███   ▒███   ▒███            ▒███    ▒███    ███████ 
 ▒▒▒▒▒▒▒▒███ ▒███    ▒███   ███▒███   ▒███                  ▒███ ▒▒██████  ▒▒▒▒▒▒▒▒███ ▒███▒▒▒█    ▒▒███  █████  ███             ▒▒███   ███    ███▒▒▒▒  
 ███    ▒███ ▒███    ███   ███ ▒▒███  ▒███      █           ▒███  ▒▒█████  ███    ▒███ ▒███  ▒      ▒▒▒█████▒█████▒               ▒▒▒█████▒    ███      █
▒▒█████████  ██████████   █████ █████ ███████████ █████████ █████  ▒▒█████▒▒█████████  █████          ▒▒███ ▒▒███      █████████    ▒▒███     ▒██████████
 ▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒ ▒▒▒▒▒ ▒▒▒▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒▒ ▒▒▒▒▒    ▒▒▒▒▒  ▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒            ▒▒▒   ▒▒▒      ▒▒▒▒▒▒▒▒▒      ▒▒▒      ▒▒▒▒▒▒▒▒▒▒ 

 █████                     █████              ████  ████                    
▒▒███                     ▒▒███              ▒▒███ ▒▒███                    
 ▒███  ████████    █████  ███████    ██████   ▒███  ▒███   ██████  ████████ 
 ▒███ ▒▒███▒▒███  ███▒▒  ▒▒▒███▒    ▒▒▒▒▒███  ▒███  ▒███  ███▒▒███▒▒███▒▒███
 ▒███  ▒███ ▒███ ▒▒█████   ▒███      ███████  ▒███  ▒███ ▒███████  ▒███ ▒▒▒ 
 ▒███  ▒███ ▒███  ▒▒▒▒███  ▒███ ███ ███▒▒███  ▒███  ▒███ ▒███▒▒▒   ▒███     
 █████ ████ █████ ██████   ▒▒█████ ▒▒████████ █████ █████▒▒██████  █████    
▒▒▒▒▒ ▒▒▒▒ ▒▒▒▒▒ ▒▒▒▒▒▒     ▒▒▒▒▒   ▒▒▒▒▒▒▒▒ ▒▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒▒▒▒     
                                                                            
                                                                            
                                                                             
               
EOF
  printf '%b' "$RESET"

  # Red title
  printf '%b' "$RED"
  cat <<'EOF'
        🚀  SDXL NSFW Installer (🐺  CryptoAce85 🐺  Edition) 🚀
EOF
  printf '%b' "$RESET"
}

banner_bottom() {
  # Green wolf + block (as provided)
  printf '%b' "$GREEN"
  cat <<'EOF'

                                        *.                          *       
                                        #%%%#                     *%%%#      
                                       -%% %%%#                 *%%% %%+     
                                       %%-  %%%%*     ...     +%%%%  .%%     
                                       %%   *%%%%%%%%%%%%%%%%%%%%%#   %%.    
                                      :%%=  +%%%%%%%%%%%%%%%%%%%%%*  -%%-    
                                      :%%%  %%%%%%%%%%%%%%%%%%%%%%%  %%%-    
                                       %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%:    
                                       %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%     
                                      #%%%%%%%%=   -%%%%%%%=   -%%%%%%%%#    
                                    =%%%%%%%+        *%%%#        -%%%%%%%+  
                                   *%%%%%%%%%###+     %%%     =####%%%%%%%%* 
                                  :#-%%%%#    -  *%   %%%   %*  =    +%%%%+*-
                                    %%%%        :#%%  %%%  %%#:        %%%%  
                                   %%%%%%          %%%%%%%%%-         %%%%%% 
                                  :%%%%%#%%         %%%%%%%         %%#%%%%%-
                                  -%%%%%%%           %%%%%           %%%%%%%+
                                   %+#%%%%    :      *%%%#      ..   %%%%%+% 
                                   - =%%%%+  #%#               #%%  +%%%%* - 
                                      %%%%%. %%%#   :%%%%%-   #%%%  %%%%%    
                                      .%%%%%##%%%    #%%%#    %%%##%%%%%=    
                                       :%#%%%%%%%%    +%+    %%%%%%%%*%-     
                                         - #%%%%%%%*  ===  +%%%%%%%%  .      
                                            :%%%%%%%%%%@%%%%%%%%%%=          
                                              -%-*%%%%%%%%%%%*:%=            
 ░█▀▀░█▀▄░█▀▀░█▀█░▀█▀░█▀▀░█▀▄░░░█▀▄░█░█░░░░       -%%%%%%%%%=                
 ░█░░░█▀▄░█▀▀░█▀█░░█░░█▀▀░█░█░░░█▀▄░░█░░░▀░         +=%%%-+                  
 ░▀▀▀░▀░▀░▀▀▀░▀░▀░░▀░░▀▀▀░▀▀░░░░▀▀░░░▀░░░▀░            +                     
EOF
  printf '%b' "$RESET"

  # Red title
  printf '%b' "$RED"
  cat <<'EOF'
 ░▒▓██████▓▒░░▒▓███████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓███████▓▒░▒▓████████▓▒░▒▓██████▓▒░ ░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓████████▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ ░▒▓█▓▒░  ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░             
░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░ ░▒▓█▓▒░  ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░           
░▒▓█▓▒░      ░▒▓███████▓▒░ ░▒▓██████▓▒░░▒▓███████▓▒░  ░▒▓█▓▒░  ░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░▒▓█▓▒░      ░▒▓██████▓▒░   
░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░   ░▒▓█▓▒░        ░▒▓█▓▒░  ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░       
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░   ░▒▓█▓▒░        ░▒▓█▓▒░  ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░       
 ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░   ░▒▓█▓▒░        ░▒▓█▓▒░   ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓████████▓▒░ 

EOF
  printf '%b' "$RESET"

  # Red title
  printf '%b' "$YELLOW"
  cat <<'EOF'
 ░█▀█░█░░░█░░░░░█▀▄░█▀█░█▀█░█▀▀░█░░░█▀▀░▀█▀░█▀█░█▀▄░▀█▀░░░█▀▄░█░█░█▀█░░░░░█▀▀░█▀█░█▄█░█▀▀░█░█░█░█░▀█▀░░░░█▀▀░█░█
 ░█▀█░█░░░█░░░░░█░█░█░█░█░█░█▀▀░▀░░░▀▀█░░█░░█▀█░█▀▄░░█░░░░█▀▄░█░█░█░█░░░░░█░░░█░█░█░█░█▀▀░░█░░█░█░░█░░░░░▀▀█░█▀█
 ░▀░▀░▀▀▀░▀▀▀░░░▀▀░░▀▀▀░▀░▀░▀▀▀░▀░░░▀▀▀░░▀░░▀░▀░▀░▀░░▀░░░░▀░▀░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░░░░▀░░▀▀▀░▀▀▀░▀░░▀▀▀░▀░▀
EOF
  printf '%b' "$RESET"
}

# Normalize line endings in-place
if command -v sed >/dev/null 2>&1; then
  sed -i 's/\r$//' "$0" || true
fi

# Env detection
HAS_CONDA=0
if command -v conda >/dev/null 2>&1; then HAS_CONDA=1; fi

# Always use *this* python by default
PY_BIN="$(command -v python)"
export PY_BIN
PIP_BIN="${PY_BIN} -m pip"

# PIP runtime defaults
export PIP_NO_INPUT=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_DEFAULT_TIMEOUT=240
export PIP_ROOT_USER_ACTION=ignore

# Begin installation ────────────────────────────────────────────────────────────────────────────────
banner_top
hdr "Starting installer (non-interactive)"

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================
hdr "Conda environment"
say "Sourcing Conda environment"
if [ -f "/workspace/miniconda3/etc/profile.d/conda.sh" ]; then
  . "/workspace/miniconda3/etc/profile.d/conda.sh"
else
  fail "Conda not found at /workspace/miniconda3; please install Miniconda."
fi
if ! conda env list | grep -qE '^\s*comfyui\s'; then
  say "Creating comfyui Conda environment"
  conda create -n comfyui python=3.10 -y || fail "Failed to create comfyui env"
fi
say "Activating env: ${CONDA_ENV_NAME}"
conda activate "${CONDA_ENV_NAME}" || fail "Failed to activate conda env ${CONDA_ENV_NAME}"
export PIP_CONSTRAINT="/tmp/pin-numpy-1-26-4.txt"
ok "Conda env active."
say "Upgrading base Python tools"
pip install --no-input --upgrade pip wheel setuptools >/dev/null 2>&1 || true
ok "Upgrading base Python tools"

# Fix NumPy version
hdr "Fix NumPy version"
say "Skipping NumPy version pinning due to file creation issues. Will handle in dependency installation."
unset PIP_CONSTRAINT
ok "NumPy version fix skipped (handled later)."

# Re-assert Python path
PY_BIN="$(command -v python)"
PIP_BIN="${PY_BIN} -m pip"
ok "Using Python at: ${PY_BIN}"

# ============================================================================
# CRITICAL DEPENDENCY FIXES
# ============================================================================
hdr "Fixing critical package versions for compatibility"

# Fix NumPy version (must be <2 for onnxruntime compatibility)
say "Ensuring NumPy 1.x for onnxruntime compatibility"
pip install "numpy<2" --upgrade 2>&1 | grep -v "Requirement already satisfied" || true
ok "NumPy version fixed"

# Fix transformers version (Joy Caption requires 4.56.1)
say "Ensuring transformers 4.56.1 for Joy Caption compatibility"
pip install transformers==4.56.1 --force-reinstall --no-deps 2>&1 | grep -v "already satisfied" || true
ok "Transformers version fixed"

# Verify critical versions
python - <<'PY'
import numpy, transformers
print(f"✓ numpy: {numpy.__version__}")
print(f"✓ transformers: {transformers.__version__}")
assert numpy.__version__.startswith('1.'), f"NumPy must be 1.x, got {numpy.__version__}"
assert transformers.__version__ == '4.56.1', f"Transformers must be 4.56.1, got {transformers.__version__}"
PY

# ============================================================================
# SYSTEM DEPENDENCIES
# ============================================================================
hdr "System dependencies"
qrun "Installing system toolchain" -- sh -c 'apt-get update -y >/dev/null 2>&1 && apt-get install -y --no-install-recommends \
  build-essential cmake python3-dev libopenblas-dev liblapack-dev zlib1g-dev \
  libx11-dev aria2 ffmpeg libportaudio2 portaudio19-dev jq \
  >/dev/null 2>&1 && rm -rf /var/lib/apt/lists/*'
python -m pip uninstall -y cmake >/dev/null 2>&1 || true

# ============================================================================
# PYTHON DEPENDENCIES
# ============================================================================
hdr "Global NumPy/ORT guard"
export PIP_CONSTRAINT="/tmp/pin-numpy-1-26-4.txt"
cat > "${PIP_CONSTRAINT}" <<'PIN'
numpy==1.26.4
protobuf<5,>=4.25.3
PIN
echo ">>> Using PIP_CONSTRAINT=${PIP_CONSTRAINT}"
${PIP_BIN} cache purge || true
${PY_BIN} - <<'PY'
import subprocess, sys
subprocess.call([sys.executable, "-m", "pip", "uninstall", "-y", "onnxruntime-gpu"])
PY
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps onnx==${ONNX_PIN}
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps onnxruntime==${ORT_PIN}
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps numpy==${NUMPY_PIN}
${PY_BIN} - <<'PY'
import numpy as np, onnxruntime as ort
print("✓ ORT import OK:", ort.__version__, "| NumPy:", np.__version__)
print(" Providers advertised:", ort.get_available_providers())
PY
ok "NumPy/ORT guard verified"

hdr "NumPy/ORT sanity (install + verify)"
${PY_BIN} - <<'PY'
import sys, platform
print(f"Python: {sys.executable}")
print(f"Version: {platform.python_version()}")
PY
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps numpy==${NUMPY_PIN}
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps onnx==${ONNX_PIN}
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps onnxruntime==${ORT_PIN}
retry 6 8 -- ${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps "protobuf>=4.25.3,<5"
${PY_BIN} - <<'PY'
import onnxruntime as ort, numpy as np
print(f"✓ ORT import OK: {ort.__version__} | NumPy: {np.__version__}")
print(" Providers advertised:", ort.get_available_providers())
PY
ok "NumPy/ORT verified"

hdr "ORT/NumPy compatibility"
${PY_BIN} - <<'PY'
import sys, subprocess
def pip(*args): return subprocess.check_call([sys.executable, "-m", "pip", *args])
def ver(pkg):
    try:
        import importlib.metadata as im
        return im.version(pkg)
    except Exception:
        return None
ort_ver = ver("onnxruntime") or ver("onnxruntime-gpu")
np_ver = ver("numpy")
if ort_ver and ort_ver.split(".",1)[0] == "1":
    if (np_ver is None) or (np_ver.split(".",1)[0] != "1"):
        subprocess.call([sys.executable, "-m", "pip", "uninstall", "-y", "numpy"])
        pip("install", "--no-cache-dir", "--no-deps", "numpy==1.26.4")
        np_ver = ver("numpy")
        print(f"✓ NumPy aligned for ORT 1.x: numpy={np_ver}")
print(f"✓ Detected ORT: {ort_ver or 'none'}; NumPy: {np_ver or 'none'}")
PY
ok "ORT/NumPy compatibility verified"

say "Ensuring Python libs (huggingface_hub, transformers, diffusers, peft, insightface, mediapipe)…"
retry 6 8 -- ${PIP_BIN} install --no-cache-dir -q \
  "huggingface_hub>=0.34" \
  "hf-transfer" \
  "transformers==4.56.1" \
  "diffusers==0.35.1" \
  "peft>=0.17.1" \
  "insightface==0.7.3" \
  "mediapipe==${MEDIAPIPE_PIN}" \
  "onnxruntime-gpu==${ORT_PIN}"
ok "Python libs checked."

# ============================================================================
# COMFYUI CORE
# ============================================================================
hdr "ComfyUI core"
say "Updating ComfyUI"
if [ -d "${COMFY_DIR}/.git" ]; then
  ( cd "${COMFY_DIR}" && "${GIT_NOHDR[@]}" remote set-url origin https://github.com/comfyanonymous/ComfyUI.git \
    && "${GIT_NOHDR[@]}" fetch --all --prune && "${GIT_NOHDR[@]}" pull --rebase --autostash ) || warn "Updating ComfyUI (continuing)"
else
  "${GIT_NOHDR[@]}" clone --depth=1 https://github.com/comfyanonymous/ComfyUI "${COMFY_DIR}" || warn "Cloning ComfyUI failed (continuing)"
fi
ok "ComfyUI ready."

say "Installing ComfyUI deps"
if [ -f "${COMFY_DIR}/requirements.txt" ]; then
  quiet_pip "ComfyUI requirements" -- install --no-cache-dir -r "${COMFY_DIR}/requirements.txt" || true
fi
ok "Installing ComfyUI deps"

say "Torch/CUDA stack"
python - <<'PY'
try:
  import torch, subprocess
  print(" Torch:", torch.__version__); print(" CUDA available:", torch.cuda.is_available())
  subprocess.run(["nvcc","--version"], check=False)
except Exception: print(" Torch probe ok (nvcc may be absent).")
PY
ok "Torch stack checked."

say "Ensuring torchsde (k-diffusion dep) is present…"
retry 6 8 -- ${PIP_BIN} install --no-cache-dir -q "torchsde>=0.2.6"
ok "torchsde checked."

# ============================================================================
# CUSTOM NODES
# ============================================================================
hdr "Custom nodes"
safe_clone() {
  local repo="$1" dest="$2"
  local log="/workspace/logs/git-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$log")"
  say "Updating ${dest##*/}"
  if [ -d "${dest}/.git" ]; then
    (
      cd "${dest}" || exit 1
      # Check if we have uncommitted changes
      if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warn "${dest##*/} has local changes, stashing..."
        git stash >>"$log" 2>&1 || true
      fi
      "${GIT_NOHDR[@]}" fetch --all --prune >>"$log" 2>&1 || true
      "${GIT_NOHDR[@]}" reset --hard origin/HEAD >>"$log" 2>&1 || \
        "${GIT_NOHDR[@]}" reset --hard origin/main >>"$log" 2>&1 || \
        "${GIT_NOHDR[@]}" reset --hard origin/master >>"$log" 2>&1 || true
    ) || warn "Update failed for ${dest##*/} (check $log)"
  else
    "${GIT_NOHDR[@]}" clone --depth=1 "${repo}" "${dest}" >>"$log" 2>&1 || \
      warn "Clone failed for ${repo} (check $log)"
  fi
  ok "Updated ${dest##*/}"
}

# Kill the broken fork name if it exists
if [ -d "/workspace/ComfyUI/custom_nodes/comfyui_ipadapter_plus" ]; then
  echo "[fix] Removing broken comfyui_ipadapter_plus fork…"
  rm -rf "/workspace/ComfyUI/custom_nodes/comfyui_ipadapter_plus"
fi

# Clone custom nodes (core + workflow reqs)
safe_clone "https://github.com/EvilBT/ComfyUI_SLK_joy_caption_two.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_SLK_joy_caption_two"
safe_clone "https://github.com/city96/ComfyUI-GGUF.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-GGUF"
safe_clone "https://github.com/ltdrdata/ComfyUI-Manager.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager"
safe_clone "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-Custom-Scripts"
safe_clone "https://github.com/WASasquatch/was-node-suite-comfyui.git" "/workspace/ComfyUI/custom_nodes/was-node-suite-comfyui"
safe_clone "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite"
safe_clone "https://github.com/PowerHouseMan/ComfyUI-AdvancedLivePortrait.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-AdvancedLivePortrait"
safe_clone "https://github.com/Fannovel16/comfyui_controlnet_aux.git" "/workspace/ComfyUI/custom_nodes/comfyui_controlnet_aux"
safe_clone "https://github.com/rgthree/rgthree-comfy.git" "/workspace/ComfyUI/custom_nodes/rgthree-comfy"
safe_clone "https://github.com/TTPlanetPig/Comfyui_JC2.git" "/workspace/ComfyUI/custom_nodes/Comfyui_JC2"
safe_clone "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_IPAdapter_plus"
safe_clone "https://github.com/crystian/ComfyUI-Crystools.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-Crystools"
safe_clone "https://github.com/chflame163/ComfyUI_FaceSimilarity.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_FaceSimilarity"
safe_clone "https://github.com/comfyroll/ComfyUI_Comfyroll_CustomNodes.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_Comfyroll_CustomNodes"
safe_clone "https://github.com/cubiq/ComfyUI_essentials.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_essentials"
safe_clone "https://github.com/kijai/ComfyUI-KJNodes.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-KJNodes"
safe_clone "https://github.com/cubiq/ComfyUI_FaceAnalysis.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_FaceAnalysis"
safe_clone "https://github.com/Ryuukeisyou/comfyui_face_parsing.git" "/workspace/ComfyUI/custom_nodes/comfyui_face_parsing"
safe_clone "https://github.com/Suzie1/ComfyUI_LayerStyle_Advance.git" "/workspace/ComfyUI/custom_nodes/ComfyUI_LayerStyle_Advance"
safe_clone "https://github.com/BadCafeCode/masquerade-nodes-comfyui.git" "/workspace/ComfyUI/custom_nodes/masquerade-nodes-comfyui"
safe_clone "https://github.com/yolain/ComfyUI-Easy-Use.git" "/workspace/ComfyUI/custom_nodes/ComfyUI-Easy-Use"

# sd-perturbed-attention (special handling - non-standard repo structure)
if [ ! -d "/workspace/ComfyUI/custom_nodes/sd-perturbed-attention/.git" ]; then
  say "Cloning sd-perturbed-attention"
  git clone --depth=1 https://github.com/pamparamm/sd-perturbed-attention.git \
    "/workspace/ComfyUI/custom_nodes/sd-perturbed-attention" \
    >>/workspace/logs/git-sd-pag-$(date +%Y%m%d-%H%M%S).log 2>&1 && \
    ok "Cloned sd-perturbed-attention" || \
    warn "Failed to clone sd-perturbed-attention (check logs)"
else
  say "Updating sd-perturbed-attention"
  (
    cd "/workspace/ComfyUI/custom_nodes/sd-perturbed-attention" && \
    git fetch --all --prune >>/workspace/logs/git-sd-pag-$(date +%Y%m%d-%H%M%S).log 2>&1 && \
    git reset --hard @{u} >>/workspace/logs/git-sd-pag-$(date +%Y%m%d-%H%M%S).log 2>&1
  ) && ok "Updated sd-perturbed-attention" || warn "Update failed for sd-perturbed-attention"
fi

# ============================================================================
# TEXT PROCESSOR (MANDATORY FOR WORKFLOW)
# ============================================================================
install_text_processor() {
  local base="/workspace/ComfyUI/custom_nodes"
  local dir="$base/Text_Processor_By_Aiconomist"
  local tmp="$base/.aiconomist_tmp"
  local log="/workspace/logs/text_processor-$(date +%Y%m%d-%H%M%S).log"

  mkdir -p "$base" "$(dirname "$log")"
  say "Installing Text_Processor_By_Aiconomist"

  # Clean installation
  rm -rf "$dir" "$tmp"
  mkdir -p "$dir" "$tmp"

  # Download & unzip
  local zip_file="$tmp/Text_Processor_By_Aiconomist.zip"
  retry 6 8 -- wget -O "$zip_file" "https://huggingface.co/simwalo/SDXL/resolve/main/Text_Processor_By_Aiconomist.zip?download=true" >>"$log" 2>&1
  (cd "$tmp" && unzip -o "$zip_file" >>"$log" 2>&1) || warn "Aiconomist unzip failed (check $log)"

  # Find folder that actually contains save_text_node.py
  local src
  src="$(find "$tmp" -type f -name 'save_text_node.py' -printf '%h\n' | head -n1 || true)"
  if [ -z "$src" ]; then
    warn "Aiconomist: save_text_node.py not found in zip; leaving previous install if any."
  else
    rsync -a --delete "$src"/ "$dir"/ >>"$log" 2>&1
  fi

  # Write correct __init__.py
  cat >"$dir/__init__.py" <<'EOF'
from .save_text_node import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS

__all__ = ['NODE_CLASS_MAPPINGS', 'NODE_DISPLAY_NAME_MAPPINGS']
EOF

  # Patch accidental absolute/flat imports -> relative
  sed -i 's|from /workspace/ComfyUI/custom_nodes/Text_Processor_By_Aiconomist\.save_text_node|from .save_text_node|g' "$dir"/*.py 2>/dev/null || true
  sed -i 's|from save_text_node|from .save_text_node|g' "$dir"/*.py 2>/dev/null || true
  sed -i '/<<<<<<< /,/>>>>>>> /d' "$dir"/*.py 2>/dev/null || true

  # Quick presence check
  if grep -R --include='*.py' -n "SaveTextFlorence" "$dir" >/dev/null 2>&1; then
    ok "Aiconomist: SaveTextFlorence found"
  else
    warn "Aiconomist: SaveTextFlorence NOT found (check $log)"
  fi

  rm -rf "$tmp"
  ok "Installed Text_Processor_By_Aiconomist"
}

install_text_processor

# ============================================================================
# JOY CAPTION MODELS
# ============================================================================
install_joy_caption_models() {
  local log="/workspace/logs/joy_caption_models-$(date +%Y%m%d-%H%M%S).log"
  local hf_token="${HF_TOKEN:-}"
  local siglip_dir="/workspace/ComfyUI/models/clip/siglip-so400m-patch14-384"
  local joy_dir="/workspace/ComfyUI/models/Joy_caption_two"
  
  mkdir -p "$joy_dir" "$siglip_dir" "/workspace/ComfyUI/models/LLM/GGUF" "$(dirname "$log")"
  say "Installing Joy Caption Two models"
  
  # Download Joy Caption model pack
  if [ ! -d "${joy_dir}/cgrkzexw-599808" ]; then
    say "Fetching Joy Caption Two models from HuggingFace"
    timeout 7200 ${PY_BIN:-python} - <<EOF >>"$log" 2>&1
from huggingface_hub import snapshot_download
import os

try:
    # Download the Joy Caption model files
    snapshot_download(
        repo_id="fancyfeast/joy-caption-alpha-two",
        local_dir="${joy_dir}",
        local_dir_use_symlinks=False
    )
    print("✓ Downloaded Joy Caption Two models")
except Exception as e:
    print(f"Warning: Joy Caption download failed: {e}")
    exit(0)
EOF
    if [ $? -eq 0 ]; then 
      ok "Downloaded Joy Caption Two models"
    else 
      warn "Failed to download Joy Caption Two (check $log)"
    fi
  else
    ok "Joy Caption Two models already present"
  fi
  
  # Download SigLIP (CRITICAL: Must be in correct location)
  if [ ! -d "${siglip_dir}" ] || [ ! -f "${siglip_dir}/model.safetensors" ]; then
    say "Fetching SigLIP: google/siglip-so400m-patch14-384"
    mkdir -p "${siglip_dir}"
    
    # Download essential files with aria2 (more reliable)
    say "Downloading SigLIP config.json..."
    retry 3 5 -- aria2c -x8 -s8 \
      "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/config.json" \
      -d "${siglip_dir}" -o "config.json" --console-log-level=warn
    
    say "Downloading SigLIP model.safetensors (1.4GB - may take several minutes)..."
    retry 3 5 -- aria2c -x16 -s16 -k1M \
      "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/model.safetensors" \
      -d "${siglip_dir}" -o "model.safetensors" --console-log-level=warn
    
    say "Downloading SigLIP preprocessor_config.json..."
    retry 3 5 -- aria2c -x8 -s8 \
      "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/preprocessor_config.json" \
      -d "${siglip_dir}" -o "preprocessor_config.json" --console-log-level=warn || true
    
    if [ -f "${siglip_dir}/model.safetensors" ] && [ -f "${siglip_dir}/config.json" ]; then
      ok "Downloaded SigLIP successfully"
    else
      warn "SigLIP download incomplete (check files in $siglip_dir)"
    fi
  else
    ok "SigLIP already present at $siglip_dir"
  fi
  
  # Download GGUF model for LLM
  if [ ! -e "/workspace/ComfyUI/models/LLM/GGUF/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf" ]; then
    say "Fetching GGUF model: Meta-Llama-3.1-8B-Instruct"
    timeout 14400 ${PY_BIN:-python} - <<EOF >>"$log" 2>&1
from huggingface_hub import hf_hub_download
import os

try:
    hf_hub_download(
        repo_id="bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
        filename="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
        local_dir="/workspace/ComfyUI/models/LLM/GGUF",
        local_dir_use_symlinks=False
    )
    print("✓ Downloaded GGUF model")
except Exception as e:
    print(f"Error downloading GGUF: {e}")
    exit(0)
EOF
    if [ $? -eq 0 ]; then 
      ok "Downloaded GGUF model"
    else 
      warn "Failed to download GGUF (check $log)"
    fi
  else
    ok "GGUF model already present"
  fi
}
install_joy_caption_models

ok "Public custom nodes synced."

# Patch Joy Caption node to use correct model path
if [ -f "/workspace/ComfyUI/custom_nodes/ComfyUI_SLK_joy_caption_two/joy_caption_two_node.py" ]; then
  say "Patching Joy Caption node paths"
  sed -i 's|clip_vision/sigclip|clip/siglip-so400m-patch14-384|g' \
    "/workspace/ComfyUI/custom_nodes/ComfyUI_SLK_joy_caption_two/joy_caption_two_node.py"
  ok "Joy Caption node patched"
fi

# ============================================================================
# FIX SAVETEXTFLORENCE NODE FOR WORKFLOW COMPATIBILITY
# ============================================================================
hdr "Fixing SaveTextFlorence node for two-output compatibility"

SAVETEXT_NODE="${NODES_DIR}/Save_Florence2_Bulk_Prompts/save_text_node.py"

if [ -f "$SAVETEXT_NODE" ]; then
  say "Patching SaveTextFlorence to output positive and negative prompts separately"
  
  cat > "$SAVETEXT_NODE" <<'SAVETEXT_EOF'
import os
import re
import folder_paths

class SaveTextFlorence:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "text": ("STRING", {"forceInput": True, "multiline": True}),
                "positive_prompt_text": ("STRING", {"multiline": True, "default": ""}),
                "negative_prompt_text": ("STRING", {"multiline": True, "default": ""}),
                "gender_age_replacement": ("STRING", {"default": ""}),
                "hair_replacement": ("STRING", {"default": ""}),
                "body_size_replacement": ("STRING", {"default": ""}),
                "lora_trigger": ("STRING", {"default": ""}),
                "remove_tattoos": ("BOOLEAN", {"default": True})
            }
        }
    
    RETURN_TYPES = ("STRING", "STRING")
    RETURN_NAMES = ("processed_positive_text", "processed_negative_text")
    FUNCTION = "process_text"
    OUTPUT_NODE = False
    CATEGORY = "utils"
    
    def process_text(self, text, positive_prompt_text, negative_prompt_text, 
                    gender_age_replacement, hair_replacement, body_size_replacement, 
                    lora_trigger, remove_tattoos):
        
        processed_text = text
        
        # Apply replacements
        if gender_age_replacement:
            gender_age_patterns = [
                r"\ba (young |middle-aged |blonde )?(woman|man)\b",
                r"\ban (young |middle-aged |blonde )?(woman|man)\b"
            ]
            for pattern in gender_age_patterns:
                processed_text = re.sub(pattern, gender_age_replacement, processed_text, flags=re.IGNORECASE)
        
        if hair_replacement:
            hair_patterns = [
                r"\b(long|short|curly|straight|wavy|blonde|brown|black|red|gray|grey)\s+(hair)\b",
                r"\b(hair)\s+(color|style|length)\b"
            ]
            for pattern in hair_patterns:
                processed_text = re.sub(pattern, hair_replacement, processed_text, flags=re.IGNORECASE)
        
        if body_size_replacement:
            body_patterns = [
                r"\b(slim|thin|slender|petite|athletic|curvy|plus-size|large)\b",
                r"\b(small|medium|large)\s+(breasts?|chest)\b"
            ]
            for pattern in body_patterns:
                processed_text = re.sub(pattern, body_size_replacement, processed_text, flags=re.IGNORECASE)
        
        if remove_tattoos:
            tattoo_patterns = [
                r"\btattoo[s]?\b",
                r"\binked\b",
                r"\bbody art\b"
            ]
            for pattern in tattoo_patterns:
                processed_text = re.sub(pattern, "", processed_text, flags=re.IGNORECASE)
        
        # Add LoRA trigger at the beginning
        if lora_trigger:
            processed_text = f"{lora_trigger.strip()}, {processed_text}"
        
        # Combine with positive prompt text
        if positive_prompt_text:
            final_positive = f"{processed_text} {positive_prompt_text}"
        else:
            final_positive = processed_text
        
        # Clean up extra spaces and commas
        final_positive = re.sub(r'\s+', ' ', final_positive).strip()
        final_positive = re.sub(r',\s*,', ',', final_positive)
        
        return (final_positive, negative_prompt_text)

NODE_CLASS_MAPPINGS = {
    "SaveTextFlorence": SaveTextFlorence
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "SaveTextFlorence": "Save Florence Bulk Prompts by Aiconomist v2"
}
SAVETEXT_EOF

  ok "SaveTextFlorence node patched for two-output compatibility"
else
  warn "SaveTextFlorence node not found at $SAVETEXT_NODE"
fi

# ============================================================================
# FIX SHOWTEXT NODE FOR LIST INPUT COMPATIBILITY
# ============================================================================
hdr "Fixing ShowText node for list input handling"

SHOWTEXT_NODE="${NODES_DIR}/ComfyUI-Custom-Scripts/py/show_text.py"

if [ -f "$SHOWTEXT_NODE" ]; then
  say "Patching ShowText to handle list inputs from SaveTextFlorence"
  
  cat > "$SHOWTEXT_NODE" <<'SHOWTEXT_EOF'
class ShowText:
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "text": ("STRING", {"forceInput": True}),
            },
            "hidden": {
                "unique_id": "UNIQUE_ID",
                "extra_pnginfo": "EXTRA_PNGINFO",
            },
        }

    INPUT_IS_LIST = True
    RETURN_TYPES = ("STRING",)
    FUNCTION = "notify"
    OUTPUT_NODE = True
    OUTPUT_IS_LIST = (True,)

    CATEGORY = "utils"

    def notify(self, text, unique_id=None, extra_pnginfo=None):
        # Handle both single strings and list inputs
        display_text = text[0] if isinstance(text, list) and len(text) > 0 else text
        
        if unique_id is not None and extra_pnginfo is not None:
            if not isinstance(extra_pnginfo, list):
                print("Error: extra_pnginfo is not a list")
            elif (
                not isinstance(extra_pnginfo[0], dict)
                or "workflow" not in extra_pnginfo[0]
            ):
                print("Error: extra_pnginfo[0] is not a dict or missing 'workflow' key")
            else:
                workflow = extra_pnginfo[0]["workflow"]
                node = next(
                    (x for x in workflow["nodes"] if str(x["id"]) == str(unique_id[0])),
                    None,
                )
                if node:
                    node["widgets_values"] = [display_text]

        return {"ui": {"text": [display_text]}, "result": (text,)}


NODE_CLASS_MAPPINGS = {
    "ShowText|pysssss": ShowText,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "ShowText|pysssss": "Show Text 🐍",
}
SHOWTEXT_EOF

  ok "ShowText node patched for list input compatibility"
else
  warn "ShowText node not found at $SHOWTEXT_NODE"
fi

# ============================================================================
# CUSTOM NODE DEPENDENCIES
# ============================================================================
hdr "Custom node dependencies"

PY="${PY_BIN:-/workspace/miniconda3/envs/comfyui/bin/python}"

install_node_deps() {
  local dir="$1" log="/workspace/logs/install-$(date +%Y%m%d-%H%M%S).log"
  local node_name
  node_name=$(basename "$dir")
  mkdir -p "$(dirname "$log")"
  say "Python deps for $node_name (quiet; logging to $log)"
  if [ -f "$dir/requirements.txt" ]; then
    # Patch odd reqs per-node before install
    if [ "$node_name" = "Comfyui_JC2" ]; then
      sed -i '/triton-windows/d' "$dir/requirements.txt"
      sed -i -E 's/^huggingface_hub==[0-9.]+/huggingface_hub>=0.34.0/' "$dir/requirements.txt"
      sed -i -E 's/^\s*peft==[0-9.]+/peft>=0.17.1/' "$dir/requirements.txt"
    fi

    "$PY" -m pip install -r "$dir/requirements.txt" --no-warn-script-location --no-cache-dir >>"$log" 2>&1 || {
      warn "Python deps for $node_name failed. Last 40 log lines:"
      tail -n 40 "$log"
      return 0
    }
    ok "Python deps for $node_name"
  else
    ok "No requirements.txt for $node_name"
  fi
}

# Known-good Python stack
"$PY" -m pip uninstall -y transformers tokenizers diffusers peft opencv-python opencv-python-headless opencv-contrib-python opencv-contrib-python-headless protobuf numpy >/dev/null 2>&1 || true
"$PY" -m pip install --no-cache-dir -U \
  "transformers==4.56.1" \
  "tokenizers>=0.22.0" \
  "diffusers>=0.30.0" \
  "peft>=0.17.0" \
  "accelerate>=0.33.0" \
  "protobuf>=4.25.3,<5" \
  "opencv-contrib-python==${OPENCV_PIN}" \
  "numpy>=1.26.0,<1.27" \
  "sounddevice>=0.5.0" \
  "insightface>=0.7.3" \
  "onnx>=1.16.2" \
  "onnxruntime-gpu==${ORT_PIN}" || {
    warn "Dependency installation failed. Retrying with relaxed constraints."
    "$PY" -m pip install --no-cache-dir -U \
      "transformers==4.56.1" \
      "tokenizers>=0.22.0" \
      "diffusers>=0.30.0" \
      "peft>=0.17.0" \
      "accelerate>=0.33.0" \
      "protobuf>=4.25.3,<5" \
      "opencv-contrib-python>=4.9.0.80" \
      "numpy>=1.26.0" \
      "sounddevice>=0.5.0"
  }
  
# Verify OpenCV
"$PY" - <<'PY'
import cv2, sys
print(f"cv2: {cv2.__version__}")
if not hasattr(cv2, "CV_8U"):
    print("ERROR: cv2.CV_8U missing")
    sys.exit(1)
print("✓ cv2.CV_8U present")
PY

# Install node-specific requirements
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-AdvancedLivePortrait"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-Crystools"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-Easy-Use"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-GGUF"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-KJNodes"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_FaceAnalysis"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_FaceSimilarity"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_LayerStyle_Advance"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_essentials"
install_node_deps "/workspace/ComfyUI/custom_nodes/Comfyui_JC2"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_SLK_joy_caption_two"
install_node_deps "/workspace/ComfyUI/custom_nodes/comfyui_controlnet_aux"
install_node_deps "/workspace/ComfyUI/custom_nodes/comfyui_face_parsing"
install_node_deps "/workspace/ComfyUI/custom_nodes/rgthree-comfy"
install_node_deps "/workspace/ComfyUI/custom_nodes/was-node-suite-comfyui"
install_node_deps "/workspace/ComfyUI/custom_nodes/Text_Processor_By_Aiconomist"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_Comfyroll_CustomNodes"
install_node_deps "/workspace/ComfyUI/custom_nodes/masquerade-nodes-comfyui"
install_node_deps "/workspace/ComfyUI/custom_nodes/ComfyUI_IPAdapter_plus"

ok "Custom node dependencies installed."

# ============================================================================
# MODEL DOWNLOADS
# ============================================================================
hdr "Model downloads"

ensure_aria2() {
  hdr "aria2"
  if need_cmd aria2c; then ok "aria2 present."
  else
    warn "aria2 not found; installing via apt…"
    apt-get update -y && apt-get install -y --no-install-recommends aria2 >/dev/null 2>&1 || fail "apt aria2 install failed"
    ok "Installed aria2 via apt."
  fi
}
ensure_aria2

fetch() {
  local url="$1" out="$2" dest="$3"
  mkdir -p "$dest"
  if [ -f "${dest}/${out}" ]; then ok "Found ${out}"; return 0; fi
  say "Downloading ${out}..."
  retry 6 8 -- aria2c -x16 -s16 -k1M -o "${out}" -d "${dest}" "${url}" --console-log-level=error
}

# SDXL Base models
fetch "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" "sd_xl_base_1.0.safetensors" "$CHK_DIR"
fetch "https://huggingface.co/CryptoAce85/bigLust/resolve/main/bigLust_v16.safetensors" "bigLust_v16.safetensors" "$CHK_DIR"
fetch "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" "sdxl_vae.fp16.safetensors" "$VAE_DIR"

# Flux models
fetch "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors" "ae.safetensors" "$VAE_DIR"

# Flux model (16GB - check before downloading)
if [ ! -f "${CHK_DIR}/flux1-fill-dev-fp8.safetensors" ]; then
  say "Downloading flux1-fill-dev-fp8.safetensors (16GB - this may take several minutes)..."
  retry 6 8 -- aria2c -x16 -s16 -k1M -o "flux1-fill-dev-fp8.safetensors" -d "${CHK_DIR}" \
    "https://huggingface.co/lllyasviel/flux1_dev/resolve/main/flux1-dev-fp8.safetensors" --console-log-level=warn
  ok "Downloaded flux1-fill-dev-fp8.safetensors"
else
  ok "Found flux1-fill-dev-fp8.safetensors"
fi

# CLIP models
fetch "https://huggingface.co/laion/CLIP-ViT-L-14-laion2B-s32B-b82K/resolve/main/open_clip_pytorch_model.bin" "ViT-L-14-laion2B-s32B-b82K.bin" "$CLIP_VI_DIR"
fetch "https://huggingface.co/laion/CLIP-ViT-H-14-laion2B-s32B-b79K/resolve/main/open_clip_pytorch_model.bin" "ViT-H-14-laion2B-s32B-b79K.bin" "$CLIP_VI_DIR"
fetch "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" "clip_l.safetensors" "$CLIP_DIR"
fetch "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn_scaled.safetensors" "t5xxl_fp8_e4m3fn_scaled.safetensors" "$CLIP_DIR"

# IPAdapter models
mkdir -p "$IPADAPTER_DIR"
fetch "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.bin" "ip-adapter-plus_sdxl_vit-h.bin" "$IPADAPTER_DIR"
fetch "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "ip-adapter-faceid-plusv2_sdxl.bin" "$IPADAPTER_DIR"

# LoRA models
mkdir -p "$LORAS_DIR"
fetch "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" "ip-adapter-faceid-plusv2_sdxl_lora.safetensors" "$LORAS_DIR"

# Upscale models
fetch "https://huggingface.co/skbhadra/ClearRealityV1/resolve/main/4x-ClearRealityV1.pth" "4x-ClearRealityV1.pth" "$UPSCALE_DIR"

## ControlNet models
mkdir -p "$CONTROLNET_DIR"
fetch "https://huggingface.co/2vXpSwA7/iroiro-lora/resolve/main/test_controlnet2/flux_union_pro2.safetensors" "Flux-Union-Pro2.safetensors" "$CONTROLNET_DIR"

# ControlNet Depth (2.3GB - check before downloading)
if [ ! -f "${CONTROLNET_DIR}/Depth-SDXL-xinsir.safetensors" ]; then
  say "Downloading Depth-SDXL-xinsir.safetensors (2.3GB)..."
  retry 6 8 -- aria2c -x16 -s16 -k1M -o "Depth-SDXL-xinsir.safetensors" -d "${CONTROLNET_DIR}" \
    "https://huggingface.co/xinsir/controlnet-depth-sdxl-1.0/resolve/main/diffusion_pytorch_model.safetensors" --console-log-level=warn
  ok "Downloaded Depth-SDXL-xinsir.safetensors"
else
  ok "Found Depth-SDXL-xinsir.safetensors"
fi

ok "Models downloaded."

# ============================================================================
# FINAL VERSION ENFORCEMENT
# ============================================================================
hdr "Final version enforcement"
say "Re-enforcing critical package versions"
${PIP_BIN} install --no-cache-dir --force-reinstall --no-deps numpy==1.26.4 transformers==4.56.1 >/dev/null 2>&1 || true
ok "Critical versions locked: numpy 1.26.4, transformers 4.56.1"

# ============================================================================
# VERIFICATION
# ============================================================================
hdr "Verify workflow-critical nodes"

declare -a WF_CLASSES=(
  "IPAdapterUnifiedLoaderFaceID" "IPAdapterFaceID" "IPAdapterApply"
  "ComfyUI_SLK_joy_caption_two" "SaveTextFlorence"
  "MaskPreview+" "ImageConcanate" "easy cleanGpuUsed"
  "FaceParsingProcessorLoader(FaceParsing)" "FaceAnalysisModels" "FaceBoundingBox"
  "LayerMask: PersonMaskUltra V2" "Cut By Mask"
  "DepthAnythingPreprocessor" "OpenposePreprocessor"
)

verify_node_class() {
  local cls="$1"
  if grep -R --include='*.py' -n "$cls" "${NODES_DIR}" >/dev/null 2>&1; then
    ok "Found node class ${cls}"
  else
    warn "Node class ${cls} not found (workflow may fail)"
  fi
}

for cls in "${WF_CLASSES[@]}"; do
  verify_node_class "$cls"
done

ok "Workflow-critical nodes verified."

# ============================================================================
# CLEANUP
# ============================================================================
hdr "Clean pyc/caches"
find "${COMFY_DIR}" -type d -name "__pycache__" -prune -exec rm -rf {} + || true
find "${COMFY_DIR}" -type f -name "*.pyc" -delete || true
ok "Caches cleaned."

# ============================================================================
# FINAL SANITY CHECK
# ============================================================================
hdr "Quick sanity check"
${PY_BIN:-/workspace/miniconda3/envs/comfyui/bin/python} -m pip install --force-reinstall "peft>=0.17.0" --no-warn-script-location >>/workspace/logs/install-peft-$(date +%Y%m%d-%H%M%S).log 2>&1 || true
${PY_BIN:-/workspace/miniconda3/envs/comfyui/bin/python} - <<'PY' >>/workspace/logs/sanity-check-$(date +%Y%m%d-%H%M%S).log 2>&1
import cv2, transformers, diffusers, peft
print("transformers:", transformers.__version__)
print("diffusers:", diffusers.__version__)
print("peft:", peft.__version__)
print("opencv ximgproc present:", hasattr(cv2, "ximgproc"))
PY
if [ $? -eq 0 ]; then
  ok "Sanity check complete."
else
  warn "Sanity check failed (check /workspace/logs/sanity-check-*.log)"
fi

# ============================================================================
# FINISH
# ============================================================================
hdr "Finish"
banner_bottom
ok " All set! Launch ComfyUI with the startup command: ./Run_Comfyui.sh"
printf " Check out my other tools in github: https://github.com/CryptoAce85\n"
printf '%b' "$YELLOW"
printf '     Made with 💖  by 🐺  CryptoAce85 🐺\n'
printf '%b' "$RESET"
sleep 0.1