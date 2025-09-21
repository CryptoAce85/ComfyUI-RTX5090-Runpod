#!/usr/bin/env bash
# install_SDXL_NSFW_V2.sh
# One-shot ComfyUI + popular nodes + model fetcher + Joy Caption Two + IP-Adapter FaceID v2.
# Targeted for RunPod-style workers (conda env: comfyui).

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

###############################################################################
# 0) prerequisites (env flags + quiet wrappers) — definitions only
###############################################################################
export PIP_NO_INPUT=1
export PIP_DEFAULT_TIMEOUT=240
export PIP_PREFER_BINARY=1
export PIP_DISABLE_PIP_VERSION_CHECK=1

# Resolve the right python each call (works before/after conda activate)
_get_py() {
  # Prefer an explicit env var if you set it later; otherwise current python
  if [[ -n "${PY_BIN:-}" && -x "${PY_BIN}" ]]; then
    printf '%s' "${PY_BIN}"
  else
    command -v python
  fi
}

# ── Quiet mode scaffolding ──────────────────────────────────────
# Set QUIET=0 to see full output again.
: "${QUIET:=1}"

LOG_DIR="/workspace/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

# Make pip/chatty tools quiet and non-interactive
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
export PIP_DEFAULT_TIMEOUT=240
export PIP_ROOT_USER_ACTION=ignore
export PYTHONWARNINGS=ignore

# Small helpers that honor QUIET and stream to a logfile
qrun() {  # qrun <label> -- <command...>
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

quiet_pip() {  # quiet_pip <label> -- <pip args...>
  local label="$1"; shift; [[ "${1:-}" == "--" ]] && shift || true
  qrun "${label}" -- python -m pip --quiet --disable-pip-version-check --no-input "$@"
}

# ── Paths & config ─────────────────────────────────────────────
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
IPADAPTER_SDXL_DIR="${IPADAPTER_DIR}/sdxl_models"  # single, canonical definition

SDXL_BASE_NAME="sd_xl_base_1.0.safetensors"
SDXL_BASE_URL="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/${SDXL_BASE_NAME}"
SDXL_REFINER_NAME="sd_xl_refiner_1.0.safetensors"
SDXL_REFINER_URL="https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/${SDXL_REFINER_NAME}"

SDXL_VAE_NAME="sdxl_vae.safetensors"
SDXL_VAE_OUT="sdxl_vae.fp16.safetensors"
SDXL_VAE_URL="https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/${SDXL_VAE_NAME}"

CLIP_L14_OUT="ViT-L-14-laion2B-s32B-b82K.bin"
CLIP_L14_URL="https://huggingface.co/laion/CLIP-ViT-L-14-laion2B-s32B-b82K/resolve/main/open_clip_pytorch_model.bin"
CLIP_H14_OUT="ViT-H-14-laion2B-s32B-b79K.bin"
CLIP_H14_URL="https://huggingface.co/laion/CLIP-ViT-H-14-laion2B-s32B-b79K/resolve/main/open_clip_pytorch_model.bin"

rule() { printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
hdr()  { printf '\n'; rule; printf "▶ %s\n" "$*"; rule; }
say()  { printf "  ▶ %s\n" "$*"; }
ok()   { printf "%b          ✓ %s%b\n" "$GREEN" "$*" "$RESET"; }
warn() { printf "%b          ⚠ %s%b\n" "$YELLOW" "$*" "$RESET"; }
die()  { printf "%b          ❌ %s%b\n" "$RED" "$*" "$RESET"; exit 1; }

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
    if [[ $n -ge $tries ]]; then die "Failed after ${tries} attempts: $*"; fi
    warn "Attempt $n failed. Retrying in ${sleep_s}s..."; sleep "$sleep_s"; sleep_s=$(( sleep_s*2 )); n=$(( n+1 ))
  done
}
ensure_conda_env() {
  hdr "Conda environment"; say "Activating env: ${CONDA_ENV_NAME}"
  if [ -f "${WORKDIR}/miniconda3/etc/profile.d/conda.sh" ]; then . "${WORKDIR}/miniconda3/etc/profile.d/conda.sh"
  elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then . "/opt/conda/etc/profile.d/conda.sh"
  else die "conda.sh not found; is Miniconda present?"; fi
  conda activate "${CONDA_ENV_NAME}" || die "Failed to activate conda env ${CONDA_ENV_NAME}"
  ok "Conda env active."
  say "Upgrading base Python tools"; pip install --no-input --upgrade pip wheel setuptools >/dev/null 2>&1 || true
  ok "Upgrading base Python tools"
}
ensure_aria2() {
  hdr "aria2"
  if need_cmd aria2c; then ok "aria2 present."
  else warn "aria2 not found; installing via conda…"
       conda install -y -n "${CONDA_ENV_NAME}" -c conda-forge aria2 >/dev/null 2>&1 || die "conda aria2 install failed"
       ok "Installed aria2 via conda."
  fi
}
fetch() { local url="$1" out="$2" dest="$3"; mkdir -p "$dest"; if [ -f "${dest}/${out}" ]; then ok "Found ${out}"; return 0; fi
          retry 6 8 -- aria2c -x16 -s16 -k1M -o "${out}" -d "${dest}" "${url}"; }

safe_clone() { local repo="$1" dest="$2"
  if [ -d "${dest}/.git" ]; then (cd "${dest}" && "${GIT_NOHDR[@]}" fetch --all --prune && "${GIT_NOHDR[@]}" pull --rebase --autostash) || warn "Update failed for ${dest}"
  else "${GIT_NOHDR[@]}" clone --depth=1 "${repo}" "${dest}"; fi
}
pip_install_req_if_any() {
  local req="$1"
  if [ -f "$req" ]; then
    quiet_pip "Python deps for $(basename "$(dirname "$req")")" -- install --no-cache-dir -r "$req" || true
  fi
}

# HuggingFace fetch (respects HF_TOKEN)
hf_fetch() {
  # hf_fetch <repo_id> <repo_type> <filename> <target_dir> <extract:0/1>
  local repo_id="$1" repo_type="$2" filename="$3" target_dir="$4" extract="${5:-0}"
  python - "$repo_id" "$repo_type" "$filename" "$target_dir" "$extract" <<'PY'
import os, sys, zipfile
from huggingface_hub import hf_hub_download
from huggingface_hub.utils import RepositoryNotFoundError, EntryNotFoundError, HfHubHTTPError, LocalEntryNotFoundError
repo_id, repo_type, filename, target_dir, extract = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]=="1"
os.makedirs(target_dir, exist_ok=True)
try:
    path = hf_hub_download(repo_id=repo_id, filename=filename, local_dir=target_dir,
                           local_dir_use_symlinks=False, resume_download=True,
                           repo_type=(None if repo_type=="default" else repo_type))
    print(f"OK {path}")
    if extract and filename.lower().endswith(".zip"):
        with zipfile.ZipFile(path, 'r') as z: z.extractall(target_dir)
        os.remove(path); print(f"OK EXTRACT {target_dir}")
    sys.exit(0)
except RepositoryNotFoundError as e: print(f"ERR REPO {e}"); sys.exit(2)
except EntryNotFoundError: print("ERR MISSING FILE"); sys.exit(3)
except LocalEntryNotFoundError as e: print(f"ERR LOCAL {e}"); sys.exit(4)
except HfHubHTTPError as e: print(f"ERR HTTP {getattr(e,'response',None) and e.response.status_code}"); sys.exit(5)
except zipfile.BadZipFile: print("ERR BADZIP"); sys.exit(6)
except Exception as e: print(f"ERR {type(e).__name__}: {e}"); sys.exit(7)
PY
  local rc=$?; if [ $rc -eq 0 ]; then ok "HF fetched ${filename}"; else warn "HF fetch failed for ${filename} (rc=$rc)"; fi
  return $rc
}

verify_node_class() { local cls="$1"
  if grep -R --include='*.py' -n "$cls" "${NODES_DIR}" >/dev/null 2>&1; then ok "Found node class ${cls}"
  else warn "Node class ${cls} not found under custom_nodes (will still start; check workflow)"; fi
}

ensure_dir_and_link() {
  # ensure_dir_and_link <src_file> <dst_dir> [dst_name]
  local src="$1" dst_dir="$2" dst_name="${3:-$(basename "$1")}"
  mkdir -p "$dst_dir"
  ln -sf "$src" "${dst_dir}/${dst_name}"
}

# Safe copy: only copy when src and dst are different real files
safe_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$(readlink -f "$src")" = "$(readlink -f "$dst")" ]; then
    ok "Skip copy (same file): $(basename "$dst")"
  else
    cp -f "$src" "$dst"
    ok "Copied $(basename "$src") → $(basename "$dst")"
  fi
}

# ── Begin ──────────────────────────────────────────────────────
banner_top
hdr "Starting installer (non-interactive)"
ensure_conda_env
# ── Global pip constraints (make downgrades impossible) ────────
CONSTRAINTS_DIR="/workspace/.pip"
CONSTRAINTS_FILE="${CONSTRAINTS_DIR}/constraints.txt"
mkdir -p "$CONSTRAINTS_DIR"
cat > "$CONSTRAINTS_FILE" <<'EOF'
# Keep NumPy & OpenCV compatible (and what your nodes expect)
numpy>=2,<2.3
opencv-contrib-python-headless==4.12.0.88
EOF
export PIP_CONSTRAINT="$CONSTRAINTS_FILE"

# Ensure we're in the right env (already in your script)
. "${WORKDIR}/miniconda3/etc/profile.d/conda.sh"
conda activate "${CONDA_ENV_NAME}" >/dev/null 2>&1 || true

# Pin helpers to this env’s python from here on
PY_BIN="$(command -v python)"
ok "Using Python at: ${PY_BIN}"

# Preinstall the pinned pair so the resolver prefers them
python -m pip install --no-cache-dir -U "numpy>=2,<2.3" "opencv-contrib-python-headless==4.12.0.88"

ensure_aria2

# ── System toolchain for building dlib ─────────────────────────
apt-get update -y && apt-get install -y --no-install-recommends \
  build-essential cmake python3-dev libopenblas-dev liblapack-dev zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

# Prefer system CMake over pip shims (harmless if not installed)
python -m pip uninstall -y cmake >/dev/null 2>&1 || true

# Ensure base libs early (HF only; OpenCV handled in fix-pack)
say "Ensuring Python libs (huggingface_hub)…"
pip install --no-cache-dir -q "huggingface_hub>=0.34" >/dev/null 2>&1 || true
ok "Python libs checked."

# ComfyUI core
hdr "ComfyUI core"
say "Updating ComfyUI"
if [ -d "${COMFY_DIR}/.git" ]; then
  ( cd "${COMFY_DIR}" && "${GIT_NOHDR[@]}" remote set-url origin https://github.com/comfyanonymous/ComfyUI.git \
    && "${GIT_NOHDR[@]}" fetch --all --prune && "${GIT_NOHDR[@]}" pull --rebase --autostash ) || warn "Updating ComfyUI (continuing)"
else "${GIT_NOHDR[@]}" clone --depth=1 https://github.com/comfyanonymous/ComfyUI "${COMFY_DIR}" || warn "Cloning ComfyUI failed (continuing)"; fi
ok "ComfyUI ready."

say "Installing ComfyUI deps"
if [ -f "${COMFY_DIR}/requirements.txt" ]; then
  quiet_pip "ComfyUI requirements" -- install --no-cache-dir -r "${COMFY_DIR}/requirements.txt" || true
fi
ok "Installing ComfyUI deps"

# Torch / CUDA probe
say "Torch/CUDA stack"
python - <<'PY'
try:
  import torch, subprocess
  print("  Torch:", torch.__version__); print("  CUDA available:", torch.cuda.is_available())
  subprocess.run(["nvcc","--version"], check=False)
except Exception: print("  Torch probe ok (nvcc may be absent).")
PY
ok "Torch stack checked."

# TorchSDE guard (prevents ModuleNotFoundError in k-diffusion)
say "Ensuring torchsde (k-diffusion dep) is present…"
pip install --no-cache-dir -q "torchsde>=0.2.6" >/dev/null 2>&1 || true
ok "torchsde checked."

# Custom nodes
hdr "Custom nodes"
mkdir -p "${NODES_DIR}"
declare -A PUB_NODES=(
  ["ComfyUI-Manager"]="https://github.com/ltdrdata/ComfyUI-Manager.git"
  ["ComfyUI-Impact-Pack"]="https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  ["ComfyUI-Impact-Subpack"]="https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git"
  ["was-node-suite-comfyui"]="https://github.com/WASasquatch/was-node-suite-comfyui.git"
  ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
  ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
  ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
  ["ComfyUI-Inspire-Pack"]="https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git"
  ["ComfyUI-AdvancedLivePortrait"]="https://github.com/Kosinkadink/ComfyUI-AdvancedLivePortrait.git"
  ["comfyui_controlnet_aux"]="https://github.com/Fannovel16/comfyui_controlnet_aux.git"
  ["ComfyUI_FaceSimilarity"]="https://github.com/chflame163/ComfyUI_FaceSimilarity.git"
  ["ComfyUI-GGUF"]="https://github.com/cubiq/ComfyUI-GGUF.git"
  ["comfyui-various"]="https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
  ["Comfyui_JC2"]="https://github.com/TTPlanetPig/Comfyui_JC2.git"
)
for name in "${!PUB_NODES[@]}"; do say "Updating ${name}"; safe_clone "${PUB_NODES[$name]}" "${NODES_DIR}/${name}"; done
ok "Public custom nodes synced."

# ── Patch: Force our fixed IPAdapterPlus.py into the repo ─────────────────────
hdr "Re-applying IPAdapterPlus.py patch (single-file installer)"

_write_ipadapter_patch() {
  local dst="$1"
  mkdir -p "$(dirname "$dst")"

  # (Optional) keep a backup of whatever was there
  [ -f "$dst" ] && cp -f "$dst" "${dst}.bak" 2>/dev/null || true

  # Write the patched IPAdapterPlus.py
  cat >"$dst" <<'PY'
# --- BEGIN: IPAdapterPlus.py (patched) ---
# NOTE: This is your known-good file. Replace the contents below with the
# exact working version you uploaded / shared earlier.

# ↓↓↓ PASTE YOUR WORKING PYTHON CONTENT HERE (entire file) ↓↓↓

import torch
import os
import math
import folder_paths
import copy

import comfy.model_management as model_management
from node_helpers import conditioning_set_values
from comfy.clip_vision import load as load_clip_vision
from comfy.sd import load_lora_for_models
import comfy.utils

import torch.nn as nn
from PIL import Image
try:
    import torchvision.transforms.v2 as T
except ImportError:
    import torchvision.transforms as T

from .image_proj_models import MLPProjModel, MLPProjModelFaceId, ProjModelFaceIdPlus, Resampler, ImageProjModel
from .CrossAttentionPatch import Attn2Replace, ipadapter_attention
from .utils import (
    encode_image_masked,
    tensor_to_size,
    contrast_adaptive_sharpening,
    tensor_to_image,
    image_to_tensor,
    ipadapter_model_loader,
    insightface_loader,
    get_clipvision_file,
    get_ipadapter_file,
    get_lora_file,
)

# set the models directory
if "ipadapter" not in folder_paths.folder_names_and_paths:
    current_paths = [os.path.join(folder_paths.models_dir, "ipadapter")]
else:
    current_paths, _ = folder_paths.folder_names_and_paths["ipadapter"]
folder_paths.folder_names_and_paths["ipadapter"] = (current_paths, folder_paths.supported_pt_extensions)

WEIGHT_TYPES = ["linear", "ease in", "ease out", 'ease in-out', 'reverse in-out', 'weak input', 'weak output', 'weak middle', 'strong middle', 'style transfer', 'composition', 'strong style transfer', 'style and composition', 'style transfer precise', 'composition precise']

"""
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 Main IPAdapter Class
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""
class IPAdapter(nn.Module):
    def __init__(self, ipadapter_model, cross_attention_dim=1024, output_cross_attention_dim=1024, clip_embeddings_dim=1024, clip_extra_context_tokens=4, is_sdxl=False, is_plus=False, is_full=False, is_faceid=False, is_portrait_unnorm=False, is_kwai_kolors=False, encoder_hid_proj=None, weight_kolors=1.0):
        super().__init__()

        self.clip_embeddings_dim = clip_embeddings_dim
        self.cross_attention_dim = cross_attention_dim
        self.output_cross_attention_dim = output_cross_attention_dim
        self.clip_extra_context_tokens = clip_extra_context_tokens
        self.is_sdxl = is_sdxl
        self.is_full = is_full
        self.is_plus = is_plus
        self.is_portrait_unnorm = is_portrait_unnorm
        self.is_kwai_kolors = is_kwai_kolors

        if is_faceid and not is_portrait_unnorm:
            self.image_proj_model = self.init_proj_faceid()
        elif is_full:
            self.image_proj_model = self.init_proj_full()
        elif is_plus or is_portrait_unnorm:
            self.image_proj_model = self.init_proj_plus()
        else:
            self.image_proj_model = self.init_proj()

        self.image_proj_model.load_state_dict(ipadapter_model["image_proj"])
        self.ip_layers = To_KV(ipadapter_model["ip_adapter"], encoder_hid_proj=encoder_hid_proj, weight_kolors=weight_kolors)

        self.multigpu_clones = {}

    def create_multigpu_clone(self, device):
        if device not in self.multigpu_clones:
            orig_multigpu_clones = self.multigpu_clones
            try:
                self.multigpu_clones = {}
                new_clone = copy.deepcopy(self)
                new_clone = new_clone.to(device)
                orig_multigpu_clones[device] = new_clone
            finally:
                self.multigpu_clones = orig_multigpu_clones

    def get_multigpu_clone(self, device):
        return self.multigpu_clones.get(device, self)

    def init_proj(self):
        image_proj_model = ImageProjModel(
            cross_attention_dim=self.cross_attention_dim,
            clip_embeddings_dim=self.clip_embeddings_dim,
            clip_extra_context_tokens=self.clip_extra_context_tokens
        )
        return image_proj_model

    def init_proj_plus(self):
        image_proj_model = Resampler(
            dim=self.cross_attention_dim,
            depth=4,
            dim_head=64,
            heads=20 if self.is_sdxl and not self.is_kwai_kolors else 12,
            num_queries=self.clip_extra_context_tokens,
            embedding_dim=self.clip_embeddings_dim,
            output_dim=self.output_cross_attention_dim,
            ff_mult=4
        )
        return image_proj_model

    def init_proj_full(self):
        image_proj_model = MLPProjModel(
            cross_attention_dim=self.cross_attention_dim,
            clip_embeddings_dim=self.clip_embeddings_dim
        )
        return image_proj_model

    def init_proj_faceid(self):
        if self.is_plus:
            image_proj_model = ProjModelFaceIdPlus(
                cross_attention_dim=self.cross_attention_dim,
                id_embeddings_dim=512,
                clip_embeddings_dim=self.clip_embeddings_dim,
                num_tokens=self.clip_extra_context_tokens,
            )
        else:
            image_proj_model = MLPProjModelFaceId(
                cross_attention_dim=self.cross_attention_dim,
                id_embeddings_dim=512,
                num_tokens=self.clip_extra_context_tokens,
            )
        return image_proj_model

    @torch.inference_mode()
    def get_image_embeds(self, clip_embed, clip_embed_zeroed, batch_size):
        torch_device = model_management.get_torch_device()
        intermediate_device = model_management.intermediate_device()

        if batch_size == 0:
            batch_size = clip_embed.shape[0]
            intermediate_device = torch_device
        elif batch_size > clip_embed.shape[0]:
            batch_size = clip_embed.shape[0]

        clip_embed = torch.split(clip_embed, batch_size, dim=0)
        clip_embed_zeroed = torch.split(clip_embed_zeroed, batch_size, dim=0)
        
        image_prompt_embeds = []
        uncond_image_prompt_embeds = []

        for ce, cez in zip(clip_embed, clip_embed_zeroed):
            image_prompt_embeds.append(self.image_proj_model(ce.to(torch_device)).to(intermediate_device))
            uncond_image_prompt_embeds.append(self.image_proj_model(cez.to(torch_device)).to(intermediate_device))

        del clip_embed, clip_embed_zeroed

        image_prompt_embeds = torch.cat(image_prompt_embeds, dim=0)
        uncond_image_prompt_embeds = torch.cat(uncond_image_prompt_embeds, dim=0)

        torch.cuda.empty_cache()

        #image_prompt_embeds = self.image_proj_model(clip_embed)
        #uncond_image_prompt_embeds = self.image_proj_model(clip_embed_zeroed)
        return image_prompt_embeds, uncond_image_prompt_embeds

    @torch.inference_mode()
    def get_image_embeds_faceid_plus(self, face_embed, clip_embed, s_scale, shortcut, batch_size):
        torch_device = model_management.get_torch_device()
        intermediate_device = model_management.intermediate_device()

        if batch_size == 0:
            batch_size = clip_embed.shape[0]
            intermediate_device = torch_device
        elif batch_size > clip_embed.shape[0]:
            batch_size = clip_embed.shape[0]

        face_embed_batch = torch.split(face_embed, batch_size, dim=0)
        clip_embed_batch = torch.split(clip_embed, batch_size, dim=0)

        embeds = []
        for face_embed, clip_embed in zip(face_embed_batch, clip_embed_batch):
            embeds.append(self.image_proj_model(face_embed.to(torch_device), clip_embed.to(torch_device), scale=s_scale, shortcut=shortcut).to(intermediate_device))

        embeds = torch.cat(embeds, dim=0)
        del face_embed_batch, clip_embed_batch
        torch.cuda.empty_cache()
        #embeds = self.image_proj_model(face_embed, clip_embed, scale=s_scale, shortcut=shortcut)
        return embeds

class To_KV(nn.Module):
    def __init__(self, state_dict, encoder_hid_proj=None, weight_kolors=1.0):
        super().__init__()

        if encoder_hid_proj is not None:
            hid_proj = nn.Linear(encoder_hid_proj["weight"].shape[1], encoder_hid_proj["weight"].shape[0], bias=True)
            hid_proj.weight.data = encoder_hid_proj["weight"] * weight_kolors
            hid_proj.bias.data = encoder_hid_proj["bias"] * weight_kolors

        self.to_kvs = nn.ModuleDict()
        for key, value in state_dict.items():
            if encoder_hid_proj is not None:
                linear_proj = nn.Linear(value.shape[1], value.shape[0], bias=False)
                linear_proj.weight.data = value
                self.to_kvs[key.replace(".weight", "").replace(".", "_")] = nn.Sequential(hid_proj, linear_proj)
            else:
                self.to_kvs[key.replace(".weight", "").replace(".", "_")] = nn.Linear(value.shape[1], value.shape[0], bias=False)
                self.to_kvs[key.replace(".weight", "").replace(".", "_")].weight.data = value

def set_model_patch_replace(model, patch_kwargs, key):
    to = model.model_options["transformer_options"].copy()
    if "patches_replace" not in to:
        to["patches_replace"] = {}
    else:
        to["patches_replace"] = to["patches_replace"].copy()

    if "attn2" not in to["patches_replace"]:
        to["patches_replace"]["attn2"] = {}
    else:
        to["patches_replace"]["attn2"] = to["patches_replace"]["attn2"].copy()

    if key not in to["patches_replace"]["attn2"]:
        to["patches_replace"]["attn2"][key] = Attn2Replace(ipadapter_attention, **patch_kwargs)
        model.model_options["transformer_options"] = to
    else:
        to["patches_replace"]["attn2"][key].add(ipadapter_attention, **patch_kwargs)

def ipadapter_execute(model,
                      ipadapter,
                      clipvision,
                      insightface=None,
                      image=None,
                      image_composition=None,
                      image_negative=None,
                      weight=1.0,
                      weight_composition=1.0,
                      weight_faceidv2=None,
                      weight_kolors=1.0,
                      weight_type="linear",
                      combine_embeds="concat",
                      start_at=0.0,
                      end_at=1.0,
                      attn_mask=None,
                      pos_embed=None,
                      neg_embed=None,
                      unfold_batch=False,
                      embeds_scaling='V only',
                      layer_weights=None,
                      encode_batch_size=0,
                      style_boost=None,
                      composition_boost=None,
                      enhance_tiles=1,
                      enhance_ratio=1.0,):
    device = model_management.get_torch_device()
    dtype = model_management.unet_dtype()
    if dtype not in [torch.float32, torch.float16, torch.bfloat16]:
        dtype = torch.float16 if model_management.should_use_fp16() else torch.float32

    is_full = "proj.3.weight" in ipadapter["image_proj"]
    is_portrait_unnorm = "portraitunnorm" in ipadapter
    is_plus = (is_full or "latents" in ipadapter["image_proj"] or "perceiver_resampler.proj_in.weight" in ipadapter["image_proj"]) and not is_portrait_unnorm
    output_cross_attention_dim = ipadapter["ip_adapter"]["1.to_k_ip.weight"].shape[1]
    is_sdxl = output_cross_attention_dim == 2048
    is_kwai_kolors_faceid = "perceiver_resampler.layers.0.0.to_out.weight" in ipadapter["image_proj"] and ipadapter["image_proj"]["perceiver_resampler.layers.0.0.to_out.weight"].shape[0] == 4096
    is_faceidv2 = "faceidplusv2" in ipadapter or is_kwai_kolors_faceid
    is_kwai_kolors = (is_sdxl and "layers.0.0.to_out.weight" in ipadapter["image_proj"] and ipadapter["image_proj"]["layers.0.0.to_out.weight"].shape[0] == 2048) or is_kwai_kolors_faceid
    is_portrait = "proj.2.weight" in ipadapter["image_proj"] and not "proj.3.weight" in ipadapter["image_proj"] and not "0.to_q_lora.down.weight" in ipadapter["ip_adapter"] and not is_kwai_kolors_faceid
    is_faceid = is_portrait or "0.to_q_lora.down.weight" in ipadapter["ip_adapter"] or is_portrait_unnorm or is_kwai_kolors_faceid

    if is_faceid and not insightface:
        raise Exception("insightface model is required for FaceID models")

    if is_faceidv2:
        weight_faceidv2 = weight_faceidv2 if weight_faceidv2 is not None else weight*2

    if is_kwai_kolors_faceid:
        cross_attention_dim = 4096
    elif is_kwai_kolors:
        cross_attention_dim = 2048
    elif (is_plus and is_sdxl and not is_faceid) or is_portrait_unnorm:
        cross_attention_dim = 1280
    else:
        cross_attention_dim = output_cross_attention_dim
    
    if is_kwai_kolors_faceid:
        clip_extra_context_tokens = 6
    elif (is_plus and not is_faceid) or is_portrait or is_portrait_unnorm:
        clip_extra_context_tokens = 16
    else:
        clip_extra_context_tokens = 4

    if image is not None and image.shape[1] != image.shape[2]:
        print("\033[33mINFO: the IPAdapter reference image is not a square, CLIPImageProcessor will resize and crop it at the center. If the main focus of the picture is not in the middle the result might not be what you are expecting.\033[0m")

    if isinstance(weight, list):
        weight = torch.tensor(weight).unsqueeze(-1).unsqueeze(-1).to(device, dtype=dtype) if unfold_batch else weight[0]

    if style_boost is not None:
        weight_type = "style transfer precise"
    elif composition_boost is not None:
        weight_type = "composition precise"

    # special weight types
    if layer_weights is not None and layer_weights != '':
        weight = { int(k): float(v)*weight for k, v in [x.split(":") for x in layer_weights.split(",")] }
        weight_type = weight_type if weight_type == "style transfer precise" or weight_type == "composition precise" else "linear"
    elif weight_type == "style transfer":
        weight = { 6:weight } if is_sdxl else { 0:weight, 1:weight, 2:weight, 3:weight, 9:weight, 10:weight, 11:weight, 12:weight, 13:weight, 14:weight, 15:weight }
    elif weight_type == "composition":
        weight = { 3:weight } if is_sdxl else { 4:weight*0.25, 5:weight }
    elif weight_type == "strong style transfer":
        if is_sdxl:
            weight = { 0:weight, 1:weight, 2:weight, 4:weight, 5:weight, 6:weight, 7:weight, 8:weight, 9:weight, 10:weight }
        else:
            weight = { 0:weight, 1:weight, 2:weight, 3:weight, 6:weight, 7:weight, 8:weight, 9:weight, 10:weight, 11:weight, 12:weight, 13:weight, 14:weight, 15:weight }
    elif weight_type == "style and composition":
        if is_sdxl:
            weight = { 3:weight_composition, 6:weight }
        else:
            weight = { 0:weight, 1:weight, 2:weight, 3:weight, 4:weight_composition*0.25, 5:weight_composition, 9:weight, 10:weight, 11:weight, 12:weight, 13:weight, 14:weight, 15:weight }
    elif weight_type == "strong style and composition":
        if is_sdxl:
            weight = { 0:weight, 1:weight, 2:weight, 3:weight_composition, 4:weight, 5:weight, 6:weight, 7:weight, 8:weight, 9:weight, 10:weight }
        else:
            weight = { 0:weight, 1:weight, 2:weight, 3:weight, 4:weight_composition, 5:weight_composition, 6:weight, 7:weight, 8:weight, 9:weight, 10:weight, 11:weight, 12:weight, 13:weight, 14:weight, 15:weight }
    elif weight_type == "style transfer precise":
        weight_composition = style_boost if style_boost is not None else weight
        if is_sdxl:
            weight = { 3:weight_composition, 6:weight }
        else:
            weight = { 0:weight, 1:weight, 2:weight, 3:weight, 4:weight_composition*0.25, 5:weight_composition, 9:weight, 10:weight, 11:weight, 12:weight, 13:weight, 14:weight, 15:weight }
    elif weight_type == "composition precise":
        weight_composition = weight
        weight = composition_boost if composition_boost is not None else weight
        if is_sdxl:
            weight = { 0:weight*.1, 1:weight*.1, 2:weight*.1, 3:weight_composition, 4:weight*.1, 5:weight*.1, 6:weight, 7:weight*.1, 8:weight*.1, 9:weight*.1, 10:weight*.1 }
        else:
            weight = { 0:weight, 1:weight, 2:weight, 3:weight, 4:weight_composition*0.25, 5:weight_composition, 6:weight*.1, 7:weight*.1, 8:weight*.1, 9:weight, 10:weight, 11:weight, 12:weight, 13:weight, 14:weight, 15:weight }

    clipvision_size = 224 if not is_kwai_kolors else 336

    img_comp_cond_embeds = None
    face_cond_embeds = None
    if is_faceid:
        if insightface is None:
            raise Exception("Insightface model is required for FaceID models")

        from insightface.utils import face_align

        insightface.det_model.input_size = (640,640) # reset the detection size
        image_iface = tensor_to_image(image)
        face_cond_embeds = []
        image = []

        for i in range(image_iface.shape[0]):
            for size in [(size, size) for size in range(640, 256, -64)]:
                insightface.det_model.input_size = size # TODO: hacky but seems to be working
                face = insightface.get(image_iface[i])
                if face:
                    if not is_portrait_unnorm:
                        face_cond_embeds.append(torch.from_numpy(face[0].normed_embedding).unsqueeze(0))
                    else:
                        face_cond_embeds.append(torch.from_numpy(face[0].embedding).unsqueeze(0))
                    image.append(image_to_tensor(face_align.norm_crop(image_iface[i], landmark=face[0].kps, image_size=336 if is_kwai_kolors_faceid else 256 if is_sdxl else 224)))

                    if 640 not in size:
                        print(f"\033[33mINFO: InsightFace detection resolution lowered to {size}.\033[0m")
                    break
            else:
                raise Exception('InsightFace: No face detected.')
        face_cond_embeds = torch.stack(face_cond_embeds).to(device, dtype=dtype)
        image = torch.stack(image)
        del image_iface, face

    if image is not None:
        img_cond_embeds = encode_image_masked(clipvision, image, batch_size=encode_batch_size, tiles=enhance_tiles, ratio=enhance_ratio, clipvision_size=clipvision_size)
        if image_composition is not None:
            img_comp_cond_embeds = encode_image_masked(clipvision, image_composition, batch_size=encode_batch_size, tiles=enhance_tiles, ratio=enhance_ratio, clipvision_size=clipvision_size)

        if is_plus:
            img_cond_embeds = img_cond_embeds.penultimate_hidden_states
            image_negative = image_negative if image_negative is not None else torch.zeros([1, clipvision_size, clipvision_size, 3])
            img_uncond_embeds = encode_image_masked(clipvision, image_negative, batch_size=encode_batch_size, clipvision_size=clipvision_size).penultimate_hidden_states
            if image_composition is not None:
                img_comp_cond_embeds = img_comp_cond_embeds.penultimate_hidden_states
        else:
            img_cond_embeds = img_cond_embeds.image_embeds if not is_faceid else face_cond_embeds
            if image_negative is not None and not is_faceid:
                img_uncond_embeds = encode_image_masked(clipvision, image_negative, batch_size=encode_batch_size, clipvision_size=clipvision_size).image_embeds
            else:
                img_uncond_embeds = torch.zeros_like(img_cond_embeds)
            if image_composition is not None:
                img_comp_cond_embeds = img_comp_cond_embeds.image_embeds
        del image_negative, image_composition

        image = None if not is_faceid else image # if it's face_id we need the cropped face for later
    elif pos_embed is not None:
        img_cond_embeds = pos_embed

        if neg_embed is not None:
            img_uncond_embeds = neg_embed
        else:
            if is_plus:
                img_uncond_embeds = encode_image_masked(clipvision, torch.zeros([1, clipvision_size, clipvision_size, 3]), clipvision_size=clipvision_size).penultimate_hidden_states
            else:
                img_uncond_embeds = torch.zeros_like(img_cond_embeds)
        del pos_embed, neg_embed
    else:
        raise Exception("Images or Embeds are required")

    # ensure that cond and uncond have the same batch size
    img_uncond_embeds = tensor_to_size(img_uncond_embeds, img_cond_embeds.shape[0])

    img_cond_embeds = img_cond_embeds.to(device, dtype=dtype)
    img_uncond_embeds = img_uncond_embeds.to(device, dtype=dtype)
    if img_comp_cond_embeds is not None:
        img_comp_cond_embeds = img_comp_cond_embeds.to(device, dtype=dtype)

    # combine the embeddings if needed
    if combine_embeds != "concat" and img_cond_embeds.shape[0] > 1 and not unfold_batch:
        if combine_embeds == "add":
            img_cond_embeds = torch.sum(img_cond_embeds, dim=0).unsqueeze(0)
            if face_cond_embeds is not None:
                face_cond_embeds = torch.sum(face_cond_embeds, dim=0).unsqueeze(0)
            if img_comp_cond_embeds is not None:
                img_comp_cond_embeds = torch.sum(img_comp_cond_embeds, dim=0).unsqueeze(0)
        elif combine_embeds == "subtract":
            img_cond_embeds = img_cond_embeds[0] - torch.mean(img_cond_embeds[1:], dim=0)
            img_cond_embeds = img_cond_embeds.unsqueeze(0)
            if face_cond_embeds is not None:
                face_cond_embeds = face_cond_embeds[0] - torch.mean(face_cond_embeds[1:], dim=0)
                face_cond_embeds = face_cond_embeds.unsqueeze(0)
            if img_comp_cond_embeds is not None:
                img_comp_cond_embeds = img_comp_cond_embeds[0] - torch.mean(img_comp_cond_embeds[1:], dim=0)
                img_comp_cond_embeds = img_comp_cond_embeds.unsqueeze(0)
        elif combine_embeds == "average":
            img_cond_embeds = torch.mean(img_cond_embeds, dim=0).unsqueeze(0)
            if face_cond_embeds is not None:
                face_cond_embeds = torch.mean(face_cond_embeds, dim=0).unsqueeze(0)
            if img_comp_cond_embeds is not None:
                img_comp_cond_embeds = torch.mean(img_comp_cond_embeds, dim=0).unsqueeze(0)
        elif combine_embeds == "norm average":
            img_cond_embeds = torch.mean(img_cond_embeds / torch.norm(img_cond_embeds, dim=0, keepdim=True), dim=0).unsqueeze(0)
            if face_cond_embeds is not None:
                face_cond_embeds = torch.mean(face_cond_embeds / torch.norm(face_cond_embeds, dim=0, keepdim=True), dim=0).unsqueeze(0)
            if img_comp_cond_embeds is not None:
                img_comp_cond_embeds = torch.mean(img_comp_cond_embeds / torch.norm(img_comp_cond_embeds, dim=0, keepdim=True), dim=0).unsqueeze(0)
        img_uncond_embeds = img_uncond_embeds[0].unsqueeze(0) # TODO: better strategy for uncond could be to average them

    if attn_mask is not None:
        attn_mask = attn_mask.to(device, dtype=dtype)

    encoder_hid_proj = None

    if is_kwai_kolors_faceid and hasattr(model.model, "diffusion_model") and hasattr(model.model.diffusion_model, "encoder_hid_proj"):
        encoder_hid_proj = model.model.diffusion_model.encoder_hid_proj.state_dict()

    ipa = IPAdapter(
        ipadapter,
        cross_attention_dim=cross_attention_dim,
        output_cross_attention_dim=output_cross_attention_dim,
        clip_embeddings_dim=img_cond_embeds.shape[-1],
        clip_extra_context_tokens=clip_extra_context_tokens,
        is_sdxl=is_sdxl,
        is_plus=is_plus,
        is_full=is_full,
        is_faceid=is_faceid,
        is_portrait_unnorm=is_portrait_unnorm,
        is_kwai_kolors=is_kwai_kolors,
        encoder_hid_proj=encoder_hid_proj,
        weight_kolors=weight_kolors
    ).to(device, dtype=dtype)

    if is_faceid and is_plus:
        cond = ipa.get_image_embeds_faceid_plus(face_cond_embeds, img_cond_embeds, weight_faceidv2, is_faceidv2, encode_batch_size)
        # TODO: check if noise helps with the uncond face embeds
        uncond = ipa.get_image_embeds_faceid_plus(torch.zeros_like(face_cond_embeds), img_uncond_embeds, weight_faceidv2, is_faceidv2, encode_batch_size)
    else:
        cond, uncond = ipa.get_image_embeds(img_cond_embeds, img_uncond_embeds, encode_batch_size)
        if img_comp_cond_embeds is not None:
            cond_comp = ipa.get_image_embeds(img_comp_cond_embeds, img_uncond_embeds, encode_batch_size)[0]

    cond = cond.to(device, dtype=dtype)
    uncond = uncond.to(device, dtype=dtype)

    cond_alt = None
    if img_comp_cond_embeds is not None:
        cond_alt = { 3: cond_comp.to(device, dtype=dtype) }

    del img_cond_embeds, img_uncond_embeds, img_comp_cond_embeds, face_cond_embeds

    sigma_start = model.get_model_object("model_sampling").percent_to_sigma(start_at)
    sigma_end = model.get_model_object("model_sampling").percent_to_sigma(end_at)

    patch_kwargs = {
        "ipadapter": ipa,
        "weight": weight,
        "cond": cond,
        "cond_alt": cond_alt,
        "uncond": uncond,
        "weight_type": weight_type,
        "mask": attn_mask,
        "sigma_start": sigma_start,
        "sigma_end": sigma_end,
        "unfold_batch": unfold_batch,
        "embeds_scaling": embeds_scaling,
    }

    number = 0
    if not is_sdxl:
        for id in [1,2,4,5,7,8]: # id of input_blocks that have cross attention
            patch_kwargs["module_key"] = str(number*2+1)
            set_model_patch_replace(model, patch_kwargs, ("input", id))
            number += 1
        for id in [3,4,5,6,7,8,9,10,11]: # id of output_blocks that have cross attention
            patch_kwargs["module_key"] = str(number*2+1)
            set_model_patch_replace(model, patch_kwargs, ("output", id))
            number += 1
        patch_kwargs["module_key"] = str(number*2+1)
        set_model_patch_replace(model, patch_kwargs, ("middle", 1))
    else:
        for id in [4,5,7,8]: # id of input_blocks that have cross attention
            block_indices = range(2) if id in [4, 5] else range(10) # transformer_depth
            for index in block_indices:
                patch_kwargs["module_key"] = str(number*2+1)
                set_model_patch_replace(model, patch_kwargs, ("input", id, index))
                number += 1
        for id in range(6): # id of output_blocks that have cross attention
            block_indices = range(2) if id in [3, 4, 5] else range(10) # transformer_depth
            for index in block_indices:
                patch_kwargs["module_key"] = str(number*2+1)
                set_model_patch_replace(model, patch_kwargs, ("output", id, index))
                number += 1
        for index in range(10):
            patch_kwargs["module_key"] = str(number*2+1)
            set_model_patch_replace(model, patch_kwargs, ("middle", 1, index))
            number += 1

    return (model, image)

"""
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 Loaders
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""
class IPAdapterUnifiedLoader:
    def __init__(self):
        self.lora = None
        self.clipvision = { "file": None, "model": None }
        self.ipadapter = { "file": None, "model": None }
        self.insightface = { "provider": None, "model": None }

    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "model": ("MODEL", ),
            "preset": (['LIGHT - SD1.5 only (low strength)', 'STANDARD (medium strength)', 'VIT-G (medium strength)', 'PLUS (high strength)', 'PLUS FACE (portraits)', 'FULL FACE - SD1.5 only (portraits stronger)'], ),
        },
        "optional": {
            "ipadapter": ("IPADAPTER", ),
        }}

    RETURN_TYPES = ("MODEL", "IPADAPTER", )
    RETURN_NAMES = ("model", "ipadapter", )
    FUNCTION = "load_models"
    CATEGORY = "ipadapter"

    def load_models(self, model, preset, lora_strength=0.0, provider="CPU", ipadapter=None):
        pipeline = { "clipvision": { 'file': None, 'model': None }, "ipadapter": { 'file': None, 'model': None }, "insightface": { 'provider': None, 'model': None } }
        if ipadapter is not None:
            pipeline = ipadapter

        if 'insightface' not in pipeline:
            pipeline['insightface'] = { 'provider': None, 'model': None }

        if 'ipadapter' not in pipeline:
            pipeline['ipadapter'] = { 'file': None, 'model': None }

        if 'clipvision' not in pipeline:
            pipeline['clipvision'] = { 'file': None, 'model': None }

        # 1. Load the clipvision model
        clipvision_file = get_clipvision_file(preset)
        if clipvision_file is None:
            raise Exception("ClipVision model not found.")

        if clipvision_file != self.clipvision['file']:
            if clipvision_file != pipeline['clipvision']['file']:
                self.clipvision['file'] = clipvision_file
                self.clipvision['model'] = load_clip_vision(clipvision_file)
                print(f"\033[33mINFO: Clip Vision model loaded from {clipvision_file}\033[0m")
            else:
                self.clipvision = pipeline['clipvision']

        # 2. Load the ipadapter model
        is_sdxl = isinstance(model.model, (comfy.model_base.SDXL, comfy.model_base.SDXLRefiner, comfy.model_base.SDXL_instructpix2pix))
        ipadapter_file, is_insightface, lora_pattern = get_ipadapter_file(preset, is_sdxl)
        if ipadapter_file is None:
            raise Exception("IPAdapter model not found.")

        if ipadapter_file != self.ipadapter['file']:
            if pipeline['ipadapter']['file'] != ipadapter_file:
                self.ipadapter['file'] = ipadapter_file
                self.ipadapter['model'] = ipadapter_model_loader(ipadapter_file)
                print(f"\033[33mINFO: IPAdapter model loaded from {ipadapter_file}\033[0m")
            else:
                self.ipadapter = pipeline['ipadapter']

        # 3. Load the lora model if needed
        if lora_pattern is not None:
            lora_file = get_lora_file(lora_pattern)
            lora_model = None
            if lora_file is None:
                raise Exception("LoRA model not found.")

            if self.lora is not None:
                if lora_file == self.lora['file']:
                    lora_model = self.lora['model']
                else:
                    self.lora = None
                    torch.cuda.empty_cache()

            if lora_model is None:
                lora_model = comfy.utils.load_torch_file(lora_file, safe_load=True)
                self.lora = { 'file': lora_file, 'model': lora_model }
                print(f"\033[33mINFO: LoRA model loaded from {lora_file}\033[0m")

            if lora_strength > 0:
                model, _ = load_lora_for_models(model, None, lora_model, lora_strength, 0)

        # 4. Load the insightface model if needed
        if is_insightface:
            if provider != self.insightface['provider']:
                if pipeline['insightface']['provider'] != provider:
                    self.insightface['provider'] = provider
                    self.insightface['model'] = insightface_loader(provider)
                    print(f"\033[33mINFO: InsightFace model loaded with {provider} provider\033[0m")
                else:
                    self.insightface = pipeline['insightface']

        return (model, { 'clipvision': self.clipvision, 'ipadapter': self.ipadapter, 'insightface': self.insightface }, )

class IPAdapterUnifiedLoaderFaceID(IPAdapterUnifiedLoader):
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "model": ("MODEL", ),
            "preset": (['FACEID', 'FACEID PLUS - SD1.5 only', 'FACEID PLUS V2', 'FACEID PORTRAIT (style transfer)', 'FACEID PORTRAIT UNNORM - SDXL only (strong)'], ),
            "lora_strength": ("FLOAT", { "default": 0.6, "min": 0, "max": 1, "step": 0.01 }),
            "provider": (["CPU", "CUDA", "ROCM", "DirectML", "OpenVINO", "CoreML"], ),
        },
        "optional": {
            "ipadapter": ("IPADAPTER", ),
        }}

    RETURN_NAMES = ("MODEL", "ipadapter", )
    CATEGORY = "ipadapter/faceid"

class IPAdapterUnifiedLoaderCommunity(IPAdapterUnifiedLoader):
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "model": ("MODEL", ),
            "preset": (['Composition', 'Kolors'], ),
        },
        "optional": {
            "ipadapter": ("IPADAPTER", ),
        }}

    CATEGORY = "ipadapter/loaders"

class IPAdapterModelLoader:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": { "ipadapter_file": (folder_paths.get_filename_list("ipadapter"), )}}

    RETURN_TYPES = ("IPADAPTER",)
    FUNCTION = "load_ipadapter_model"
    CATEGORY = "ipadapter/loaders"

    def load_ipadapter_model(self, ipadapter_file):
        ipadapter_file = folder_paths.get_full_path("ipadapter", ipadapter_file)
        return (ipadapter_model_loader(ipadapter_file),)

class IPAdapterInsightFaceLoader:
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "provider": (["CPU", "CUDA", "ROCM"], ),
                "model_name": (['buffalo_l', 'antelopev2'], )
            },
        }

    RETURN_TYPES = ("INSIGHTFACE",)
    FUNCTION = "load_insightface"
    CATEGORY = "ipadapter/loaders"

    def load_insightface(self, provider, model_name):
        return (insightface_loader(provider, model_name=model_name),)

"""
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 Main Apply Nodes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""
class IPAdapterSimple:
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 3, "step": 0.05 }),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "weight_type": (['standard', 'prompt is more important', 'style transfer'], ),
            },
            "optional": {
                "attn_mask": ("MASK",),
            }
        }

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "apply_ipadapter"
    CATEGORY = "ipadapter"

    def apply_ipadapter(self, model, ipadapter, image, weight, start_at, end_at, weight_type, attn_mask=None):
        if weight_type.startswith("style"):
            weight_type = "style transfer"
        elif weight_type == "prompt is more important":
            weight_type = "ease out"
        else:
            weight_type = "linear"

        ipa_args = {
            "image": image,
            "weight": weight,
            "start_at": start_at,
            "end_at": end_at,
            "attn_mask": attn_mask,
            "weight_type": weight_type,
            "insightface": ipadapter['insightface']['model'] if 'insightface' in ipadapter else None,
        }

        if 'ipadapter' not in ipadapter:
            raise Exception("IPAdapter model not present in the pipeline. Please load the models with the IPAdapterUnifiedLoader node.")
        if 'clipvision' not in ipadapter:
            raise Exception("CLIPVision model not present in the pipeline. Please load the models with the IPAdapterUnifiedLoader node.")

        return ipadapter_execute(model.clone(), ipadapter['ipadapter']['model'], ipadapter['clipvision']['model'], **ipa_args)

class IPAdapterAdvanced:
    def __init__(self):
        self.unfold_batch = False

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "apply_ipadapter"
    CATEGORY = "ipadapter"

    def apply_ipadapter(self, model, ipadapter, start_at=0.0, end_at=1.0, weight=1.0, weight_style=1.0, weight_composition=1.0, expand_style=False, weight_type="linear", combine_embeds="concat", weight_faceidv2=None, image=None, image_style=None, image_composition=None, image_negative=None, clip_vision=None, attn_mask=None, insightface=None, embeds_scaling='V only', layer_weights=None, ipadapter_params=None, encode_batch_size=0, style_boost=None, composition_boost=None, enhance_tiles=1, enhance_ratio=1.0, weight_kolors=1.0):
        is_sdxl = isinstance(model.model, (comfy.model_base.SDXL, comfy.model_base.SDXLRefiner, comfy.model_base.SDXL_instructpix2pix))

        if 'ipadapter' in ipadapter:
            ipadapter_model = ipadapter['ipadapter']['model']
            clip_vision = clip_vision if clip_vision is not None else ipadapter['clipvision']['model']
        else:
            ipadapter_model = ipadapter

        if clip_vision is None:
            raise Exception("Missing CLIPVision model.")

        if image_style is not None: # we are doing style + composition transfer
            if not is_sdxl:
                raise Exception("Style + Composition transfer is only available for SDXL models at the moment.") # TODO: check feasibility for SD1.5 models

            image = image_style
            weight = weight_style
            if image_composition is None:
                image_composition = image_style

            weight_type = "strong style and composition" if expand_style else "style and composition"
        if ipadapter_params is not None: # we are doing batch processing
            image = ipadapter_params['image']
            attn_mask = ipadapter_params['attn_mask']
            weight = ipadapter_params['weight']
            weight_type = ipadapter_params['weight_type']
            start_at = ipadapter_params['start_at']
            end_at = ipadapter_params['end_at']
        else:
            # at this point weight can be a list from the batch-weight or a single float
            weight = [weight]

        image = image if isinstance(image, list) else [image]

        work_model = model.clone()

        for i in range(len(image)):
            if image[i] is None:
                continue

            ipa_args = {
                "image": image[i],
                "image_composition": image_composition,
                "image_negative": image_negative,
                "weight": weight[i],
                "weight_composition": weight_composition,
                "weight_faceidv2": weight_faceidv2,
                "weight_type": weight_type if not isinstance(weight_type, list) else weight_type[i],
                "combine_embeds": combine_embeds,
                "start_at": start_at if not isinstance(start_at, list) else start_at[i],
                "end_at": end_at if not isinstance(end_at, list) else end_at[i],
                "attn_mask": attn_mask if not isinstance(attn_mask, list) else attn_mask[i],
                "unfold_batch": self.unfold_batch,
                "embeds_scaling": embeds_scaling,
                "insightface": insightface if insightface is not None else ipadapter['insightface']['model'] if 'insightface' in ipadapter else None,
                "layer_weights": layer_weights,
                "encode_batch_size": encode_batch_size,
                "style_boost": style_boost,
                "composition_boost": composition_boost,
                "enhance_tiles": enhance_tiles,
                "enhance_ratio": enhance_ratio,
                "weight_kolors": weight_kolors,
            }

            work_model, face_image = ipadapter_execute(work_model, ipadapter_model, clip_vision, **ipa_args)

        del ipadapter
        return (work_model, face_image, )

class IPAdapterBatch(IPAdapterAdvanced):
    def __init__(self):
        self.unfold_batch = True

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
                "encode_batch_size": ("INT", { "default": 0, "min": 0, "max": 4096 }),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

class IPAdapterStyleComposition(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image_style": ("IMAGE",),
                "image_composition": ("IMAGE",),
                "weight_style": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_composition": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "expand_style": ("BOOLEAN", { "default": False }),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"], {"default": "average"}),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    CATEGORY = "ipadapter/style_composition"

class IPAdapterStyleCompositionBatch(IPAdapterStyleComposition):
    def __init__(self):
        self.unfold_batch = True

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image_style": ("IMAGE",),
                "image_composition": ("IMAGE",),
                "weight_style": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_composition": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "expand_style": ("BOOLEAN", { "default": False }),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

class IPAdapterFaceID(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 3, "step": 0.05 }),
                "weight_faceidv2": ("FLOAT", { "default": 1.0, "min": -1, "max": 5.0, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
                "insightface": ("INSIGHTFACE",),
            }
        }

    CATEGORY = "ipadapter/faceid"
    RETURN_TYPES = ("MODEL","IMAGE",)
    RETURN_NAMES = ("MODEL", "face_image", )

class IPAAdapterFaceIDBatch(IPAdapterFaceID):
    def __init__(self):
        self.unfold_batch = True

class IPAdapterFaceIDKolors(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 3, "step": 0.05 }),
                "weight_faceidv2": ("FLOAT", { "default": 1.0, "min": -1, "max": 5.0, "step": 0.05 }),
                "weight_kolors": ("FLOAT", { "default": 1.0, "min": -1, "max": 5.0, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
                "insightface": ("INSIGHTFACE",),
            }
        }

    CATEGORY = "ipadapter/faceid"
    RETURN_TYPES = ("MODEL","IMAGE",)
    RETURN_NAMES = ("MODEL", "face_image", )

class IPAdapterTiled:
    def __init__(self):
        self.unfold_batch = False

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 3, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "sharpening": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    RETURN_TYPES = ("MODEL", "IMAGE", "MASK", )
    RETURN_NAMES = ("MODEL", "tiles", "masks", )
    FUNCTION = "apply_tiled"
    CATEGORY = "ipadapter/tiled"

    def apply_tiled(self, model, ipadapter, image, weight, weight_type, start_at, end_at, sharpening, combine_embeds="concat", image_negative=None, attn_mask=None, clip_vision=None, embeds_scaling='V only', encode_batch_size=0):
        # 1. Select the models
        if 'ipadapter' in ipadapter:
            ipadapter_model = ipadapter['ipadapter']['model']
            clip_vision = clip_vision if clip_vision is not None else ipadapter['clipvision']['model']
        else:
            ipadapter_model = ipadapter
            clip_vision = clip_vision

        if clip_vision is None:
            raise Exception("Missing CLIPVision model.")

        del ipadapter

        # 2. Extract the tiles
        tile_size = 256     # I'm using 256 instead of 224 as it is more likely divisible by the latent size, it will be downscaled to 224 by the clip vision encoder
        _, oh, ow, _ = image.shape
        if attn_mask is None:
            attn_mask = torch.ones([1, oh, ow], dtype=image.dtype, device=image.device)

        image = image.permute([0,3,1,2])
        attn_mask = attn_mask.unsqueeze(1)
        # the mask should have the same proportions as the reference image and the latent
        attn_mask = T.Resize((oh, ow), interpolation=T.InterpolationMode.BICUBIC, antialias=True)(attn_mask)

        # if the image is almost a square, we crop it to a square
        if oh / ow > 0.75 and oh / ow < 1.33:
            # crop the image to a square
            image = T.CenterCrop(min(oh, ow))(image)
            resize = (tile_size*2, tile_size*2)

            attn_mask = T.CenterCrop(min(oh, ow))(attn_mask)
        # otherwise resize the smallest side and the other proportionally
        else:
            resize = (int(tile_size * ow / oh), tile_size) if oh < ow else (tile_size, int(tile_size * oh / ow))

         # using PIL for better results
        imgs = []
        for img in image:
            img = T.ToPILImage()(img)
            img = img.resize(resize, resample=Image.Resampling['LANCZOS'])
            imgs.append(T.ToTensor()(img))
        image = torch.stack(imgs)
        del imgs, img

        # we don't need a high quality resize for the mask
        attn_mask = T.Resize(resize[::-1], interpolation=T.InterpolationMode.BICUBIC, antialias=True)(attn_mask)

        # we allow a maximum of 4 tiles
        if oh / ow > 4 or oh / ow < 0.25:
            crop = (tile_size, tile_size*4) if oh < ow else (tile_size*4, tile_size)
            image = T.CenterCrop(crop)(image)
            attn_mask = T.CenterCrop(crop)(attn_mask)

        attn_mask = attn_mask.squeeze(1)

        if sharpening > 0:
            image = contrast_adaptive_sharpening(image, sharpening)

        image = image.permute([0,2,3,1])

        _, oh, ow, _ = image.shape

        # find the number of tiles for each side
        tiles_x = math.ceil(ow / tile_size)
        tiles_y = math.ceil(oh / tile_size)
        overlap_x = max(0, (tiles_x * tile_size - ow) / (tiles_x - 1 if tiles_x > 1 else 1))
        overlap_y = max(0, (tiles_y * tile_size - oh) / (tiles_y - 1 if tiles_y > 1 else 1))

        base_mask = torch.zeros([attn_mask.shape[0], oh, ow], dtype=image.dtype, device=image.device)

        # extract all the tiles from the image and create the masks
        tiles = []
        masks = []
        for y in range(tiles_y):
            for x in range(tiles_x):
                start_x = int(x * (tile_size - overlap_x))
                start_y = int(y * (tile_size - overlap_y))
                tiles.append(image[:, start_y:start_y+tile_size, start_x:start_x+tile_size, :])
                mask = base_mask.clone()
                mask[:, start_y:start_y+tile_size, start_x:start_x+tile_size] = attn_mask[:, start_y:start_y+tile_size, start_x:start_x+tile_size]
                masks.append(mask)
        del mask

        # 3. Apply the ipadapter to each group of tiles
        model = model.clone()
        for i in range(len(tiles)):
            ipa_args = {
                "image": tiles[i],
                "image_negative": image_negative,
                "weight": weight,
                "weight_type": weight_type,
                "combine_embeds": combine_embeds,
                "start_at": start_at,
                "end_at": end_at,
                "attn_mask": masks[i],
                "unfold_batch": self.unfold_batch,
                "embeds_scaling": embeds_scaling,
                "encode_batch_size": encode_batch_size,
            }
            # apply the ipadapter to the model without cloning it
            model, _ = ipadapter_execute(model, ipadapter_model, clip_vision, **ipa_args)

        return (model, torch.cat(tiles), torch.cat(masks), )

class IPAdapterTiledBatch(IPAdapterTiled):
    def __init__(self):
        self.unfold_batch = True

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 3, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "sharpening": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
                "encode_batch_size": ("INT", { "default": 0, "min": 0, "max": 4096 }),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

class IPAdapterEmbeds:
    def __init__(self):
        self.unfold_batch = False

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "pos_embed": ("EMBEDS",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 3, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "neg_embed": ("EMBEDS",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "apply_ipadapter"
    CATEGORY = "ipadapter/embeds"

    def apply_ipadapter(self, model, ipadapter, pos_embed, weight, weight_type, start_at, end_at, neg_embed=None, attn_mask=None, clip_vision=None, embeds_scaling='V only'):
        ipa_args = {
            "pos_embed": pos_embed,
            "neg_embed": neg_embed,
            "weight": weight,
            "weight_type": weight_type,
            "start_at": start_at,
            "end_at": end_at,
            "attn_mask": attn_mask,
            "embeds_scaling": embeds_scaling,
            "unfold_batch": self.unfold_batch,
        }

        if 'ipadapter' in ipadapter:
            ipadapter_model = ipadapter['ipadapter']['model']
            clip_vision = clip_vision if clip_vision is not None else ipadapter['clipvision']['model']
        else:
            ipadapter_model = ipadapter
            clip_vision = clip_vision

        if clip_vision is None and neg_embed is None:
            raise Exception("Missing CLIPVision model.")

        del ipadapter

        return ipadapter_execute(model.clone(), ipadapter_model, clip_vision, **ipa_args)

class IPAdapterEmbedsBatch(IPAdapterEmbeds):
    def __init__(self):
        self.unfold_batch = True

class IPAdapterMS(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_faceidv2": ("FLOAT", { "default": 1.0, "min": -1, "max": 5.0, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
                "layer_weights": ("STRING", { "default": "", "multiline": True }),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
                "insightface": ("INSIGHTFACE",),
            }
        }

    CATEGORY = "ipadapter/dev"

class IPAdapterClipVisionEnhancer(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
                "enhance_tiles": ("INT", { "default": 2, "min": 1, "max": 16 }),
                "enhance_ratio": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05 }),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    CATEGORY = "ipadapter/dev"

class IPAdapterClipVisionEnhancerBatch(IPAdapterClipVisionEnhancer):
    def __init__(self):
        self.unfold_batch = True

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "weight_type": (WEIGHT_TYPES, ),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
                "enhance_tiles": ("INT", { "default": 2, "min": 1, "max": 16 }),
                "enhance_ratio": ("FLOAT", { "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05 }),
                "encode_batch_size": ("INT", { "default": 0, "min": 0, "max": 4096 }),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

class IPAdapterFromParams(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "ipadapter_params": ("IPADAPTER_PARAMS", ),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    CATEGORY = "ipadapter/params"

class IPAdapterPreciseStyleTransfer(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "style_boost": ("FLOAT", { "default": 1.0, "min": -5, "max": 5, "step": 0.05 }),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

class IPAdapterPreciseStyleTransferBatch(IPAdapterPreciseStyleTransfer):
    def __init__(self):
        self.unfold_batch = True

class IPAdapterPreciseComposition(IPAdapterAdvanced):
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "model": ("MODEL", ),
                "ipadapter": ("IPADAPTER", ),
                "image": ("IMAGE",),
                "weight": ("FLOAT", { "default": 1.0, "min": -1, "max": 5, "step": 0.05 }),
                "composition_boost": ("FLOAT", { "default": 0.0, "min": -5, "max": 5, "step": 0.05 }),
                "combine_embeds": (["concat", "add", "subtract", "average", "norm average"],),
                "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
                "embeds_scaling": (['V only', 'K+V', 'K+V w/ C penalty', 'K+mean(V) w/ C penalty'], ),
            },
            "optional": {
                "image_negative": ("IMAGE",),
                "attn_mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

class IPAdapterPreciseCompositionBatch(IPAdapterPreciseComposition):
    def __init__(self):
        self.unfold_batch = True

"""
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 Helpers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""
class IPAdapterEncoder:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "ipadapter": ("IPADAPTER",),
            "image": ("IMAGE",),
            "weight": ("FLOAT", { "default": 1.0, "min": -1.0, "max": 3.0, "step": 0.01 }),
            },
            "optional": {
                "mask": ("MASK",),
                "clip_vision": ("CLIP_VISION",),
            }
        }

    RETURN_TYPES = ("EMBEDS", "EMBEDS",)
    RETURN_NAMES = ("pos_embed", "neg_embed",)
    FUNCTION = "encode"
    CATEGORY = "ipadapter/embeds"

    def encode(self, ipadapter, image, weight, mask=None, clip_vision=None):
        if 'ipadapter' in ipadapter:
            ipadapter_model = ipadapter['ipadapter']['model']
            clip_vision = clip_vision if clip_vision is not None else ipadapter['clipvision']['model']
        else:
            ipadapter_model = ipadapter
            clip_vision = clip_vision

        if clip_vision is None:
            raise Exception("Missing CLIPVision model.")

        is_plus = "proj.3.weight" in ipadapter_model["image_proj"] or "latents" in ipadapter_model["image_proj"] or "perceiver_resampler.proj_in.weight" in ipadapter_model["image_proj"]
        is_kwai_kolors = is_plus and "layers.0.0.to_out.weight" in ipadapter_model["image_proj"] and ipadapter_model["image_proj"]["layers.0.0.to_out.weight"].shape[0] == 2048

        clipvision_size = 224 if not is_kwai_kolors else 336

        # resize and crop the mask to 224x224
        if mask is not None and mask.shape[1:3] != torch.Size([clipvision_size, clipvision_size]):
            mask = mask.unsqueeze(1)
            transforms = T.Compose([
                T.CenterCrop(min(mask.shape[2], mask.shape[3])),
                T.Resize((clipvision_size, clipvision_size), interpolation=T.InterpolationMode.BICUBIC, antialias=True),
            ])
            mask = transforms(mask).squeeze(1)
            #mask = T.Resize((image.shape[1], image.shape[2]), interpolation=T.InterpolationMode.BICUBIC, antialias=True)(mask.unsqueeze(1)).squeeze(1)

        img_cond_embeds = encode_image_masked(clip_vision, image, mask, clipvision_size=clipvision_size)

        if is_plus:
            img_cond_embeds = img_cond_embeds.penultimate_hidden_states
            img_uncond_embeds = encode_image_masked(clip_vision, torch.zeros([1, clipvision_size, clipvision_size, 3]), clipvision_size=clipvision_size).penultimate_hidden_states
        else:
            img_cond_embeds = img_cond_embeds.image_embeds
            img_uncond_embeds = torch.zeros_like(img_cond_embeds)

        if weight != 1:
            img_cond_embeds = img_cond_embeds * weight

        return (img_cond_embeds, img_uncond_embeds, )

class IPAdapterCombineEmbeds:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "embed1": ("EMBEDS",),
            "method": (["concat", "add", "subtract", "average", "norm average", "max", "min"], ),
        },
        "optional": {
            "embed2": ("EMBEDS",),
            "embed3": ("EMBEDS",),
            "embed4": ("EMBEDS",),
            "embed5": ("EMBEDS",),
        }}

    RETURN_TYPES = ("EMBEDS",)
    FUNCTION = "batch"
    CATEGORY = "ipadapter/embeds"

    def batch(self, embed1, method, embed2=None, embed3=None, embed4=None, embed5=None):
        if method=='concat' and embed2 is None and embed3 is None and embed4 is None and embed5 is None:
            return (embed1, )

        embeds = [embed1, embed2, embed3, embed4, embed5]
        embeds = [embed for embed in embeds if embed is not None]
        embeds = torch.cat(embeds, dim=0)

        if method == "add":
            embeds = torch.sum(embeds, dim=0).unsqueeze(0)
        elif method == "subtract":
            embeds = embeds[0] - torch.mean(embeds[1:], dim=0)
            embeds = embeds.unsqueeze(0)
        elif method == "average":
            embeds = torch.mean(embeds, dim=0).unsqueeze(0)
        elif method == "norm average":
            embeds = torch.mean(embeds / torch.norm(embeds, dim=0, keepdim=True), dim=0).unsqueeze(0)
        elif method == "max":
            embeds = torch.max(embeds, dim=0).values.unsqueeze(0)
        elif method == "min":
            embeds = torch.min(embeds, dim=0).values.unsqueeze(0)

        return (embeds, )

class IPAdapterNoise:
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "type": (["fade", "dissolve", "gaussian", "shuffle"], ),
                "strength": ("FLOAT", { "default": 1.0, "min": 0, "max": 1, "step": 0.05 }),
                "blur": ("INT", { "default": 0, "min": 0, "max": 32, "step": 1 }),
            },
            "optional": {
                "image_optional": ("IMAGE",),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "make_noise"
    CATEGORY = "ipadapter/utils"

    def make_noise(self, type, strength, blur, image_optional=None):
        if image_optional is None:
            image = torch.zeros([1, 224, 224, 3])
        else:
            transforms = T.Compose([
                T.CenterCrop(min(image_optional.shape[1], image_optional.shape[2])),
                T.Resize((224, 224), interpolation=T.InterpolationMode.BICUBIC, antialias=True),
            ])
            image = transforms(image_optional.permute([0,3,1,2])).permute([0,2,3,1])

        seed = int(torch.sum(image).item()) % 1000000007 # hash the image to get a seed, grants predictability
        torch.manual_seed(seed)

        if type == "fade":
            noise = torch.rand_like(image)
            noise = image * (1 - strength) + noise * strength
        elif type == "dissolve":
            mask = (torch.rand_like(image) < strength).float()
            noise = torch.rand_like(image)
            noise = image * (1-mask) + noise * mask
        elif type == "gaussian":
            noise = torch.randn_like(image) * strength
            noise = image + noise
        elif type == "shuffle":
            transforms = T.Compose([
                T.ElasticTransform(alpha=75.0, sigma=(1-strength)*3.5),
                T.RandomVerticalFlip(p=1.0),
                T.RandomHorizontalFlip(p=1.0),
            ])
            image = transforms(image.permute([0,3,1,2])).permute([0,2,3,1])
            noise = torch.randn_like(image) * (strength*0.75)
            noise = image * (1-noise) + noise

        del image
        noise = torch.clamp(noise, 0, 1)

        if blur > 0:
            if blur % 2 == 0:
                blur += 1
            noise = T.functional.gaussian_blur(noise.permute([0,3,1,2]), blur).permute([0,2,3,1])

        return (noise, )

class PrepImageForClipVision:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "image": ("IMAGE",),
            "interpolation": (["LANCZOS", "BICUBIC", "HAMMING", "BILINEAR", "BOX", "NEAREST"],),
            "crop_position": (["top", "bottom", "left", "right", "center", "pad"],),
            "sharpening": ("FLOAT", {"default": 0.0, "min": 0, "max": 1, "step": 0.05}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "prep_image"

    CATEGORY = "ipadapter/utils"

    def prep_image(self, image, interpolation="LANCZOS", crop_position="center", sharpening=0.0):
        size = (224, 224)
        _, oh, ow, _ = image.shape
        output = image.permute([0,3,1,2])

        if crop_position == "pad":
            if oh != ow:
                if oh > ow:
                    pad = (oh - ow) // 2
                    pad = (pad, 0, pad, 0)
                elif ow > oh:
                    pad = (ow - oh) // 2
                    pad = (0, pad, 0, pad)
                output = T.functional.pad(output, pad, fill=0)
        else:
            crop_size = min(oh, ow)
            x = (ow-crop_size) // 2
            y = (oh-crop_size) // 2
            if "top" in crop_position:
                y = 0
            elif "bottom" in crop_position:
                y = oh-crop_size
            elif "left" in crop_position:
                x = 0
            elif "right" in crop_position:
                x = ow-crop_size

            x2 = x+crop_size
            y2 = y+crop_size

            output = output[:, :, y:y2, x:x2]

        imgs = []
        for img in output:
            img = T.ToPILImage()(img) # using PIL for better results
            img = img.resize(size, resample=Image.Resampling[interpolation])
            imgs.append(T.ToTensor()(img))
        output = torch.stack(imgs, dim=0)
        del imgs, img

        if sharpening > 0:
            output = contrast_adaptive_sharpening(output, sharpening)

        output = output.permute([0,2,3,1])

        return (output, )

class IPAdapterSaveEmbeds:
    def __init__(self):
        self.output_dir = folder_paths.get_output_directory()

    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "embeds": ("EMBEDS",),
            "filename_prefix": ("STRING", {"default": "IP_embeds"})
            },
        }

    RETURN_TYPES = ()
    FUNCTION = "save"
    OUTPUT_NODE = True
    CATEGORY = "ipadapter/embeds"

    def save(self, embeds, filename_prefix):
        full_output_folder, filename, counter, subfolder, filename_prefix = folder_paths.get_save_image_path(filename_prefix, self.output_dir)
        file = f"{filename}_{counter:05}.ipadpt"
        file = os.path.join(full_output_folder, file)

        torch.save(embeds, file)
        return (None, )

class IPAdapterLoadEmbeds:
    @classmethod
    def INPUT_TYPES(s):
        input_dir = folder_paths.get_input_directory()
        files = [os.path.relpath(os.path.join(root, file), input_dir) for root, dirs, files in os.walk(input_dir) for file in files if file.endswith('.ipadpt')]
        return {"required": {"embeds": [sorted(files), ]}, }

    RETURN_TYPES = ("EMBEDS", )
    FUNCTION = "load"
    CATEGORY = "ipadapter/embeds"

    def load(self, embeds):
        path = folder_paths.get_annotated_filepath(embeds)
        return (torch.load(path).cpu(), )

class IPAdapterWeights:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "weights": ("STRING", {"default": '1.0, 0.0', "multiline": True }),
            "timing": (["custom", "linear", "ease_in_out", "ease_in", "ease_out", "random"], { "default": "linear" } ),
            "frames": ("INT", {"default": 0, "min": 0, "max": 9999, "step": 1 }),
            "start_frame": ("INT", {"default": 0, "min": 0, "max": 9999, "step": 1 }),
            "end_frame": ("INT", {"default": 9999, "min": 0, "max": 9999, "step": 1 }),
            "add_starting_frames": ("INT", {"default": 0, "min": 0, "max": 9999, "step": 1 }),
            "add_ending_frames": ("INT", {"default": 0, "min": 0, "max": 9999, "step": 1 }),
            "method": (["full batch", "shift batches", "alternate batches"], { "default": "full batch" }),
            }, "optional": {
                "image": ("IMAGE",),
            }
        }

    RETURN_TYPES = ("FLOAT", "FLOAT", "INT", "IMAGE", "IMAGE", "WEIGHTS_STRATEGY")
    RETURN_NAMES = ("weights", "weights_invert", "total_frames", "image_1", "image_2", "weights_strategy")
    FUNCTION = "weights"
    CATEGORY = "ipadapter/weights"

    def weights(self, weights='', timing='custom', frames=0, start_frame=0, end_frame=9999, add_starting_frames=0, add_ending_frames=0, method='full batch', weights_strategy=None, image=None):
        import random

        frame_count = image.shape[0] if image is not None else 0
        if weights_strategy is not None:
            weights = weights_strategy["weights"]
            timing = weights_strategy["timing"]
            frames = weights_strategy["frames"]
            start_frame = weights_strategy["start_frame"]
            end_frame = weights_strategy["end_frame"]
            add_starting_frames = weights_strategy["add_starting_frames"]
            add_ending_frames = weights_strategy["add_ending_frames"]
            method = weights_strategy["method"]
            frame_count = weights_strategy["frame_count"]
        else:
            weights_strategy = {
                "weights": weights,
                "timing": timing,
                "frames": frames,
                "start_frame": start_frame,
                "end_frame": end_frame,
                "add_starting_frames": add_starting_frames,
                "add_ending_frames": add_ending_frames,
                "method": method,
                "frame_count": frame_count,
            }

        # convert the string to a list of floats separated by commas or newlines
        weights = weights.replace("\n", ",")
        weights = [float(weight) for weight in weights.split(",") if weight.strip() != ""]

        if timing != "custom":
            frames = max(frames, 2)
            start = 0.0
            end = 1.0

            if len(weights) > 0:
                start = weights[0]
                end = weights[-1]

            weights = []

            end_frame = min(end_frame, frames)
            duration = end_frame - start_frame
            if start_frame > 0:
                weights.extend([start] * start_frame)

            for i in range(duration):
                n = duration - 1
                if timing == "linear":
                    weights.append(start + (end - start) * i / n)
                elif timing == "ease_in_out":
                    weights.append(start + (end - start) * (1 - math.cos(i / n * math.pi)) / 2)
                elif timing == "ease_in":
                    weights.append(start + (end - start) * math.sin(i / n * math.pi / 2))
                elif timing == "ease_out":
                    weights.append(start + (end - start) * (1 - math.cos(i / n * math.pi / 2)))
                elif timing == "random":
                    weights.append(random.uniform(start, end))

            weights[-1] = end if timing != "random" else weights[-1]
            if end_frame < frames:
                weights.extend([end] * (frames - end_frame))

        if len(weights) == 0:
            weights = [0.0]

        frames = len(weights)

        # repeat the images for cross fade
        image_1 = None
        image_2 = None

        # Calculate the min and max of the weights
        min_weight = min(weights)
        max_weight = max(weights)

        if image is not None:

            if "shift" in method:
                image_1 = image[:-1]
                image_2 = image[1:]

                weights = weights * image_1.shape[0]
                image_1 = image_1.repeat_interleave(frames, 0)
                image_2 = image_2.repeat_interleave(frames, 0)
            elif "alternate" in method:
                image_1 = image[::2].repeat_interleave(2, 0)
                image_1 = image_1[1:]
                image_2 = image[1::2].repeat_interleave(2, 0)

                # Invert the weights relative to their own range
                mew_weights = weights + [max_weight - (w - min_weight) for w in weights]

                mew_weights = mew_weights * (image_1.shape[0] // 2)
                if image.shape[0] % 2:
                    image_1 = image_1[:-1]
                else:
                    image_2 = image_2[:-1]
                    mew_weights = mew_weights + weights

                weights = mew_weights
                image_1 = image_1.repeat_interleave(frames, 0)
                image_2 = image_2.repeat_interleave(frames, 0)
            else:
                weights = weights * image.shape[0]
                image_1 = image.repeat_interleave(frames, 0)

            # add starting and ending frames
            if add_starting_frames > 0:
                weights = [weights[0]] * add_starting_frames + weights
                image_1 = torch.cat([image[:1].repeat(add_starting_frames, 1, 1, 1), image_1], dim=0)
                if image_2 is not None:
                    image_2 = torch.cat([image[:1].repeat(add_starting_frames, 1, 1, 1), image_2], dim=0)
            if add_ending_frames > 0:
                weights = weights + [weights[-1]] * add_ending_frames
                image_1 = torch.cat([image_1, image[-1:].repeat(add_ending_frames, 1, 1, 1)], dim=0)
                if image_2 is not None:
                    image_2 = torch.cat([image_2, image[-1:].repeat(add_ending_frames, 1, 1, 1)], dim=0)

        # reverse the weights array
        weights_invert = weights[::-1]

        frame_count = len(weights)

        return (weights, weights_invert, frame_count, image_1, image_2, weights_strategy,)

class IPAdapterWeightsFromStrategy(IPAdapterWeights):
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "weights_strategy": ("WEIGHTS_STRATEGY",),
            }, "optional": {
                "image": ("IMAGE",),
            }
        }

class IPAdapterPromptScheduleFromWeightsStrategy():
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "weights_strategy": ("WEIGHTS_STRATEGY",),
            "prompt": ("STRING", {"default": "", "multiline": True }),
            }}

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("prompt_schedule", )
    FUNCTION = "prompt_schedule"
    CATEGORY = "ipadapter/weights"

    def prompt_schedule(self, weights_strategy, prompt=""):
        frames = weights_strategy["frames"]
        add_starting_frames = weights_strategy["add_starting_frames"]
        add_ending_frames = weights_strategy["add_ending_frames"]
        frame_count = weights_strategy["frame_count"]

        out = ""

        prompt = [p for p in prompt.split("\n") if p.strip() != ""]

        if len(prompt) > 0 and frame_count > 0:
            # prompt_pos must be the same size as the image batch
            if len(prompt) > frame_count:
                prompt = prompt[:frame_count]
            elif len(prompt) < frame_count:
                prompt += [prompt[-1]] * (frame_count - len(prompt))

            if add_starting_frames > 0:
                out += f"\"0\": \"{prompt[0]}\",\n"
            for i in range(frame_count):
                out += f"\"{i * frames + add_starting_frames}\": \"{prompt[i]}\",\n"
            if add_ending_frames > 0:
                out += f"\"{frame_count * frames + add_starting_frames}\": \"{prompt[-1]}\",\n"

        return (out, )

class IPAdapterCombineWeights:
    @classmethod
    def INPUT_TYPES(s):
        return {
        "required": {
            "weights_1": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05 }),
            "weights_2": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05 }),
        }}
    RETURN_TYPES = ("FLOAT", "INT")
    RETURN_NAMES = ("weights", "count")
    FUNCTION = "combine"
    CATEGORY = "ipadapter/utils"

    def combine(self, weights_1, weights_2):
        if not isinstance(weights_1, list):
            weights_1 = [weights_1]
        if not isinstance(weights_2, list):
            weights_2 = [weights_2]
        weights = weights_1 + weights_2

        return (weights, len(weights), )

class IPAdapterRegionalConditioning:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            #"set_cond_area": (["default", "mask bounds"],),
            "image": ("IMAGE",),
            "image_weight": ("FLOAT", { "default": 1.0, "min": -1.0, "max": 3.0, "step": 0.05 }),
            "prompt_weight": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 10.0, "step": 0.05 }),
            "weight_type": (WEIGHT_TYPES, ),
            "start_at": ("FLOAT", { "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
            "end_at": ("FLOAT", { "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001 }),
        }, "optional": {
            "mask": ("MASK",),
            "positive": ("CONDITIONING",),
            "negative": ("CONDITIONING",),
        }}

    RETURN_TYPES = ("IPADAPTER_PARAMS", "CONDITIONING", "CONDITIONING", )
    RETURN_NAMES = ("IPADAPTER_PARAMS", "POSITIVE", "NEGATIVE")
    FUNCTION = "conditioning"

    CATEGORY = "ipadapter/params"

    def conditioning(self, image, image_weight, prompt_weight, weight_type, start_at, end_at, mask=None, positive=None, negative=None):
        set_area_to_bounds = False #if set_cond_area == "default" else True

        if mask is not None:
            if positive is not None:
                positive = conditioning_set_values(positive, {"mask": mask, "set_area_to_bounds": set_area_to_bounds, "mask_strength": prompt_weight})
            if negative is not None:
                negative = conditioning_set_values(negative, {"mask": mask, "set_area_to_bounds": set_area_to_bounds, "mask_strength": prompt_weight})

        ipadapter_params = {
            "image": [image],
            "attn_mask": [mask],
            "weight": [image_weight],
            "weight_type": [weight_type],
            "start_at": [start_at],
            "end_at": [end_at],
        }

        return (ipadapter_params, positive, negative, )

class IPAdapterCombineParams:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {
            "params_1": ("IPADAPTER_PARAMS",),
            "params_2": ("IPADAPTER_PARAMS",),
        }, "optional": {
            "params_3": ("IPADAPTER_PARAMS",),
            "params_4": ("IPADAPTER_PARAMS",),
            "params_5": ("IPADAPTER_PARAMS",),
        }}

    RETURN_TYPES = ("IPADAPTER_PARAMS",)
    FUNCTION = "combine"
    CATEGORY = "ipadapter/params"

    def combine(self, params_1, params_2, params_3=None, params_4=None, params_5=None):
        ipadapter_params = {
            "image": params_1["image"] + params_2["image"],
            "attn_mask": params_1["attn_mask"] + params_2["attn_mask"],
            "weight": params_1["weight"] + params_2["weight"],
            "weight_type": params_1["weight_type"] + params_2["weight_type"],
            "start_at": params_1["start_at"] + params_2["start_at"],
            "end_at": params_1["end_at"] + params_2["end_at"],
        }

        if params_3 is not None:
            ipadapter_params["image"] += params_3["image"]
            ipadapter_params["attn_mask"] += params_3["attn_mask"]
            ipadapter_params["weight"] += params_3["weight"]
            ipadapter_params["weight_type"] += params_3["weight_type"]
            ipadapter_params["start_at"] += params_3["start_at"]
            ipadapter_params["end_at"] += params_3["end_at"]
        if params_4 is not None:
            ipadapter_params["image"] += params_4["image"]
            ipadapter_params["attn_mask"] += params_4["attn_mask"]
            ipadapter_params["weight"] += params_4["weight"]
            ipadapter_params["weight_type"] += params_4["weight_type"]
            ipadapter_params["start_at"] += params_4["start_at"]
            ipadapter_params["end_at"] += params_4["end_at"]
        if params_5 is not None:
            ipadapter_params["image"] += params_5["image"]
            ipadapter_params["attn_mask"] += params_5["attn_mask"]
            ipadapter_params["weight"] += params_5["weight"]
            ipadapter_params["weight_type"] += params_5["weight_type"]
            ipadapter_params["start_at"] += params_5["start_at"]
            ipadapter_params["end_at"] += params_5["end_at"]

        return (ipadapter_params, )

"""
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 Register
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""
NODE_CLASS_MAPPINGS = {
    # Main Apply Nodes
    "IPAdapter": IPAdapterSimple,
    "IPAdapterAdvanced": IPAdapterAdvanced,
    "IPAdapterBatch": IPAdapterBatch,
    "IPAdapterFaceID": IPAdapterFaceID,
    "IPAdapterFaceIDKolors": IPAdapterFaceIDKolors,
    "IPAAdapterFaceIDBatch": IPAAdapterFaceIDBatch,
    "IPAdapterTiled": IPAdapterTiled,
    "IPAdapterTiledBatch": IPAdapterTiledBatch,
    "IPAdapterEmbeds": IPAdapterEmbeds,
    "IPAdapterEmbedsBatch": IPAdapterEmbedsBatch,
    "IPAdapterStyleComposition": IPAdapterStyleComposition,
    "IPAdapterStyleCompositionBatch": IPAdapterStyleCompositionBatch,
    "IPAdapterMS": IPAdapterMS,
    "IPAdapterClipVisionEnhancer": IPAdapterClipVisionEnhancer,
    "IPAdapterClipVisionEnhancerBatch": IPAdapterClipVisionEnhancerBatch,
    "IPAdapterFromParams": IPAdapterFromParams,
    "IPAdapterPreciseStyleTransfer": IPAdapterPreciseStyleTransfer,
    "IPAdapterPreciseStyleTransferBatch": IPAdapterPreciseStyleTransferBatch,
    "IPAdapterPreciseComposition": IPAdapterPreciseComposition,
    "IPAdapterPreciseCompositionBatch": IPAdapterPreciseCompositionBatch,

    # Loaders
    "IPAdapterUnifiedLoader": IPAdapterUnifiedLoader,
    "IPAdapterUnifiedLoaderFaceID": IPAdapterUnifiedLoaderFaceID,
    "IPAdapterModelLoader": IPAdapterModelLoader,
    "IPAdapterInsightFaceLoader": IPAdapterInsightFaceLoader,
    "IPAdapterUnifiedLoaderCommunity": IPAdapterUnifiedLoaderCommunity,

    # Helpers
    "IPAdapterEncoder": IPAdapterEncoder,
    "IPAdapterCombineEmbeds": IPAdapterCombineEmbeds,
    "IPAdapterNoise": IPAdapterNoise,
    "PrepImageForClipVision": PrepImageForClipVision,
    "IPAdapterSaveEmbeds": IPAdapterSaveEmbeds,
    "IPAdapterLoadEmbeds": IPAdapterLoadEmbeds,
    "IPAdapterWeights": IPAdapterWeights,
    "IPAdapterCombineWeights": IPAdapterCombineWeights,
    "IPAdapterWeightsFromStrategy": IPAdapterWeightsFromStrategy,
    "IPAdapterPromptScheduleFromWeightsStrategy": IPAdapterPromptScheduleFromWeightsStrategy,
    "IPAdapterRegionalConditioning": IPAdapterRegionalConditioning,
    "IPAdapterCombineParams": IPAdapterCombineParams,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    # Main Apply Nodes
    "IPAdapter": "IPAdapter",
    "IPAdapterAdvanced": "IPAdapter Advanced",
    "IPAdapterBatch": "IPAdapter Batch (Adv.)",
    "IPAdapterFaceID": "IPAdapter FaceID",
    "IPAdapterFaceIDKolors": "IPAdapter FaceID Kolors",
    "IPAAdapterFaceIDBatch": "IPAdapter FaceID Batch",
    "IPAdapterTiled": "IPAdapter Tiled",
    "IPAdapterTiledBatch": "IPAdapter Tiled Batch",
    "IPAdapterEmbeds": "IPAdapter Embeds",
    "IPAdapterEmbedsBatch": "IPAdapter Embeds Batch",
    "IPAdapterStyleComposition": "IPAdapter Style & Composition SDXL",
    "IPAdapterStyleCompositionBatch": "IPAdapter Style & Composition Batch SDXL",
    "IPAdapterMS": "IPAdapter Mad Scientist",
    "IPAdapterClipVisionEnhancer": "IPAdapter ClipVision Enhancer",
    "IPAdapterClipVisionEnhancerBatch": "IPAdapter ClipVision Enhancer Batch",
    "IPAdapterFromParams": "IPAdapter from Params",
    "IPAdapterPreciseStyleTransfer": "IPAdapter Precise Style Transfer",
    "IPAdapterPreciseStyleTransferBatch": "IPAdapter Precise Style Transfer Batch",
    "IPAdapterPreciseComposition": "IPAdapter Precise Composition",
    "IPAdapterPreciseCompositionBatch": "IPAdapter Precise Composition Batch",

    # Loaders
    "IPAdapterUnifiedLoader": "IPAdapter Unified Loader",
    "IPAdapterUnifiedLoaderFaceID": "IPAdapter Unified Loader FaceID",
    "IPAdapterModelLoader": "IPAdapter Model Loader",
    "IPAdapterInsightFaceLoader": "IPAdapter InsightFace Loader",
    "IPAdapterUnifiedLoaderCommunity": "IPAdapter Unified Loader Community",

    # Helpers
    "IPAdapterEncoder": "IPAdapter Encoder",
    "IPAdapterCombineEmbeds": "IPAdapter Combine Embeds",
    "IPAdapterNoise": "IPAdapter Noise",
    "PrepImageForClipVision": "Prep Image For ClipVision",
    "IPAdapterSaveEmbeds": "IPAdapter Save Embeds",
    "IPAdapterLoadEmbeds": "IPAdapter Load Embeds",
    "IPAdapterWeights": "IPAdapter Weights",
    "IPAdapterWeightsFromStrategy": "IPAdapter Weights From Strategy",
    "IPAdapterPromptScheduleFromWeightsStrategy": "Prompt Schedule From Weights Strategy",
    "IPAdapterCombineWeights": "IPAdapter Combine Weights",
    "IPAdapterRegionalConditioning": "IPAdapter Regional Conditioning",
    "IPAdapterCombineParams": "IPAdapter Combine Params",
}
# --- END: IPAdapterPlus.py (patched) ---
PY

  chmod 644 "$dst"
  echo "✓ Wrote patch to: $dst"
}

# Apply to both common folder names used by the node
for D in \
  "/workspace/ComfyUI/custom_nodes/comfyui_ipadapter_plus" \
  "/workspace/ComfyUI/custom_nodes/ComfyUI_IPAdapter_plus"
do
  if [ -d "$D" ]; then
    _write_ipadapter_patch "$D/IPAdapterPlus.py"
  fi
done

# (Optional) sanity log
ls -l /workspace/ComfyUI/custom_nodes/*ipadapter_plus/IPAdapterPlus.py 2>/dev/null || true
# ──────────────────────────────────────────────────────────────────────────────

# Clean leftover broken private repo
if [ -d "${NODES_DIR}/ComfyUI_Various" ]; then warn "Removing stray custom_nodes/ComfyUI_Various"; rm -rf "${NODES_DIR}/ComfyUI_Various" || true; ok "Removed broken ComfyUI_Various."; fi

# Node requirements
pip_install_req_if_any "${NODES_DIR}/ComfyUI-Impact-Subpack/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/was-node-suite-comfyui/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/rgthree-comfy/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/ComfyUI_essentials/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/ComfyUI-VideoHelperSuite/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/ComfyUI-Inspire-Pack/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/ComfyUI-AdvancedLivePortrait/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/comfyui_controlnet_aux/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/ComfyUI_FaceSimilarity/requirements.txt"
pip_install_req_if_any "${NODES_DIR}/ComfyUI-GGUF/requirements.txt"

# Normalize & relax pinned versions in JC2 requirements
if [ -f "${NODES_DIR}/Comfyui_JC2/requirements.txt" ]; then
  sed -i 's/\r$//' "${NODES_DIR}/Comfyui_JC2/requirements.txt"
  sed -i -E '/^\s*triton-windows([<=>].*)?$/d' "${NODES_DIR}/Comfyui_JC2/requirements.txt"
  sed -i -E 's/^huggingface_hub==[0-9.]+/huggingface_hub>=0.34.0/' "${NODES_DIR}/Comfyui_JC2/requirements.txt"
  sed -i -E 's/^\s*peft==[0-9.]+/peft>=0.17.1/' "${NODES_DIR}/Comfyui_JC2/requirements.txt"
fi
pip_install_req_if_any "${NODES_DIR}/Comfyui_JC2/requirements.txt"

# ── Aiconomist extras (HF) ─────────────────────────────────────
hdr "Aiconomist extras (HF)"

# Text Processor node
if [ -d "${COMFY_DIR}/custom_nodes/Text_Processor_By_Aiconomist" ]; then
  ok "Text_Processor_By_Aiconomist already present; skipping download."
else
  hf_fetch "simwalo/SDXL" "model" "Text_Processor_By_Aiconomist.zip" \
           "${COMFY_DIR}/custom_nodes" 1 || warn "Could not fetch Aiconomist Text Processor"
fi

# Joy Caption Two model pack
if [ -d "${COMFY_DIR}/models/Joy_caption_two" ]; then
  ok "Joy_caption_two already present; skipping download."
else
  hf_fetch "simwalo/custom_nodes" "dataset" "Joy_caption_two.zip" \
           "${COMFY_DIR}/models" 1 || warn "Could not fetch Joy_caption_two"
fi
verify_node_class "SaveTextFlorence"

# ── Workflow model pack (Flux + LoRAs) ─────────────────────────
hdr "Workflow model pack (Flux + LoRAs)"
mkdir -p "${UNET_DIR}" "${CLIP_DIR}" "${LORAS_DIR}" "${LORAS_SDXL_DIR}"

# UNet
say "Fetching UNet: flux1-fill-dev-fp8.safetensors"
hf_fetch "simwalo/FluxDevFP8" "dataset" "flux1-fill-dev-fp8.safetensors" "${UNET_DIR}" 0

# CLIPs
say "Fetching CLIP: clip_l.safetensors"
hf_fetch "simwalo/FluxDevFP8" "dataset" "clip_l.safetensors" "${CLIP_DIR}" 0
say "Fetching CLIP: t5xxl_fp8_e4m3fn_scaled.safetensors"
hf_fetch "simwalo/FluxDevFP8" "dataset" "t5xxl_fp8_e4m3fn_scaled.safetensors" "${CLIP_DIR}" 0

# Ensure base paths exist even under `set -u`
: "${COMFY_DIR:=/workspace/ComfyUI}"
: "${MODELS_DIR:=${COMFY_DIR}/models}"

###############################################################################
# ControlNet: Flux-Union-Pro2 (+ JasperAI Upscaler FP8)
###############################################################################
hdr "ControlNet models"
CONTROLNET_DIR="${MODELS_DIR}/controlnet"
mkdir -p "${CONTROLNET_DIR}"

# Flux-Union-Pro2 (needed by your workflow)
say "Fetching ControlNet: Flux-Union-Pro2.safetensors -> controlnet/"
hf_fetch "simwalo/FluxDevFP8" "dataset" "Flux-Union-Pro2.safetensors" "${CONTROLNET_DIR}" 0

# JasperAI upscaler FP8 (your extra)
say "Fetching ControlNet: Flux1-controlnet-upscaler-Jasperai-fp8.safetensors -> controlnet/"
hf_fetch "simwalo/FluxDevFP8" "dataset" "Flux1-controlnet-upscaler-Jasperai-fp8.safetensors" "${CONTROLNET_DIR}" 0

# Sanity — make sure Comfy sees them
if ! [ -s "${CONTROLNET_DIR}/Flux-Union-Pro2.safetensors" ]; then
  warn "Flux-Union-Pro2.safetensors is missing or empty in ${CONTROLNET_DIR}"
fi

###############################################################################
# Extra LoRAs (SDXL): Small Nipples XL
###############################################################################
hdr "Extra LoRAs (SDXL)"
LORAS_DIR="${MODELS_DIR}/loras"
mkdir -p "${LORAS_DIR}/sdxl"

LORA_URL="https://civitai.com/api/download/models/200496?type=Model&format=SafeTensor"
LORA_FILE="Small Nipples XL.safetensors"          # exact filename you want
LORA_TARGET="${LORAS_DIR}/sdxl/${LORA_FILE}"

say "Fetching LoRA: ${LORA_FILE} -> loras/sdxl/"
# Prefer aria2 (fast + reliable); fall back to curl if needed
if command -v aria2c >/dev/null 2>&1; then
  aria2c -x16 -s16 -k1M --allow-overwrite=true \
         -d "${LORAS_DIR}/sdxl" -o "${LORA_FILE}" \
         "${LORA_URL}" >/dev/null 2>&1 || true
else
  curl -L --fail -o "${LORA_TARGET}.part" "${LORA_URL}" && mv -f "${LORA_TARGET}.part" "${LORA_TARGET}" || true
fi

# Sanity check and friendly aliases
if [ -s "${LORA_TARGET}" ]; then
  ok "LoRA ready: ${LORA_TARGET}"
  # Link into loras/ root (some nodes scan both loras/ and loras/sdxl/)
  ln -sfn "sdxl/${LORA_FILE}" "${LORAS_DIR}/${LORA_FILE}"
  # Provide an underscore alias too (avoids space issues in some UIs)
  ln -sfn "sdxl/${LORA_FILE}" "${LORAS_DIR}/Small_Nipples_XL.safetensors"
else
  warn "LoRA download failed or empty: ${LORA_TARGET}"
fi

###############################################################################
# IP-Adapter FaceID v2 (base + LoRA) — normalize names/paths for the workflow
###############################################################################
IPAD_DIR="${MODELS_DIR}/ipadapter"
LORAS_DIR="${MODELS_DIR}/loras"
mkdir -p "${IPAD_DIR}/sdxl_models" "${LORAS_DIR}"

BASE_TGT="${IPAD_DIR}/sdxl_models/ip_adapter_faceid_plusv2_sdxl.safetensors"
LORA_TGT="${IPAD_DIR}/sdxl_models/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"

# Move base model into target if it exists under common alt names
for cand in \
  "${IPAD_DIR}/ip_adapter_faceid_plusv2_sdxl.safetensors" \
  "${IPAD_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors" \
  "${IPAD_DIR}/sdxl_models/ip-adapter-faceid-plusv2_sdxl.safetensors"
do
  if [ -f "${cand}" ] && [ ! -f "${BASE_TGT}" ]; then
    mv -f "${cand}" "${BASE_TGT}"
    break
  fi
done

# Move LoRA into target if it exists under common alt names or in loras/
for cand in \
  "${LORAS_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" \
  "${LORAS_DIR}/ip_adapter_faceid_plusv2_sdxl_lora.safetensors" \
  "${IPAD_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" \
  "${IPAD_DIR}/ip_adapter_faceid_plusv2_sdxl_lora.safetensors"
do
  if [ -f "${cand}" ] && [ ! -f "${LORA_TGT}" ]; then
    mv -f "${cand}" "${LORA_TGT}"
    break
  fi
done

# Create the exact paths/names the nodes/UI expect

# Base .safetensors alias: only if the real file exists & is non-empty.
# ${BASE_TGT} should be the canonical path in sdxl_models/ to the .safetensors base.
if [ -s "${BASE_TGT}" ]; then
  ln -sfn "sdxl_models/$(basename "${BASE_TGT}")" \
          "${IPAD_DIR}/ip_adapter_faceid_plusv2_sdxl.safetensors"
else
  # No .safetensors base → make sure no dangling alias remains
  rm -f "${IPAD_DIR}/ip_adapter_faceid_plusv2_sdxl.safetensors"
fi

# (Optional but recommended) If the .bin base exists, keep its alias too:
if [ -s "${IPAD_DIR}/sdxl_models/ip_adapter_faceid_plusv2_sdxl.bin" ]; then
  ln -sfn "sdxl_models/ip_adapter_faceid_plusv2_sdxl.bin" \
          "${IPAD_DIR}/ip_adapter_faceid_plusv2_sdxl.bin"
fi

# LoRA aliases (keep as-is)
ln -sfn "${LORA_TGT}" "${LORAS_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
ln -sfn "ip-adapter-faceid-plusv2_sdxl_lora.safetensors" \
        "${LORAS_DIR}/ip_adapter_faceid_plusv2_sdxl_lora.safetensors"

# Sanity checks (warn, don’t fail)
[ -s "${CONTROLNET_DIR}/Flux-Union-Pro2.safetensors" ] || warn "Missing Flux-Union-Pro2.safetensors"
[ -s "${CONTROLNET_DIR}/Flux1-controlnet-upscaler-Jasperai-fp8.safetensors" ] || warn "Missing JasperAI upscaler"
[ -s "${BASE_TGT}" ] || warn "Missing IP-Adapter base SDXL (ip_adapter_faceid_plusv2_sdxl.safetensors)"
[ -s "${LORA_TGT}" ] || warn "Missing IP-Adapter FaceID v2 LoRA (ip-adapter-faceid-plusv2_sdxl_lora.safetensors)"

ok "Workflow model layout is ready."

###############################################################################
# IP-Adapter FaceID v2 (SDXL) — normalize (idempotent)
###############################################################################
hdr "IP-Adapter FaceID v2 (SDXL) — normalize"

# Make sure these exist even if script runs with set -u
: "${COMFY_DIR:=/workspace/ComfyUI}"
: "${MODELS_DIR:=${COMFY_DIR}/models}"

IP_DIR="${MODELS_DIR}/ipadapter"
SDXL_DIR="${IP_DIR}/sdxl_models"
LORAS_DIR="${MODELS_DIR}/loras"

mkdir -p "${SDXL_DIR}" "${LORAS_DIR}"

# Helper: move only when needed; succeed if src==dst (prevents set -e exit)
safe_move() {  # safe_move <src> <dst>
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  if [ -e "$dst" ] && [ "$(readlink -f "$src")" = "$(readlink -f "$dst")" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  mv -f "$src" "$dst"
}

# ---- Base backbone (bin/safetensors) ----
BASE_BIN="ip_adapter_faceid_plusv2_sdxl.bin"
BASE_SFT="ip_adapter_faceid_plusv2_sdxl.safetensors"

# Prefer a .safetensors base if present; .bin acceptable fallback
for cand in \
  "${SDXL_DIR}/${BASE_SFT}" \
  "${IP_DIR}/${BASE_SFT}" \
  "${SDXL_DIR}/${BASE_BIN}" \
  "${IP_DIR}/${BASE_BIN}"
do
  if [ -s "$cand" ]; then
    case "$cand" in
      *.safetensors) safe_move "$cand" "${SDXL_DIR}/${BASE_SFT}"; ok "Base -> ${SDXL_DIR}/${BASE_SFT}"; break;;
      *.bin)         safe_move "$cand" "${SDXL_DIR}/${BASE_BIN}"; ok "Base -> ${SDXL_DIR}/${BASE_BIN}";;
    esac
  fi
done

# Keep a friendly alias in ipadapter/ for nodes that expect it there
if [ -s "${SDXL_DIR}/${BASE_SFT}" ]; then
  ln -sfn "sdxl_models/${BASE_SFT}" "${IP_DIR}/${BASE_SFT}"
elif [ -s "${SDXL_DIR}/${BASE_BIN}" ]; then
  ln -sfn "sdxl_models/${BASE_BIN}" "${IP_DIR}/${BASE_BIN}"
fi

# ---- LoRA weights (FaceID v2 SDXL) ----
LORA_CANON="ip-adapter-faceid-plusv2_sdxl_lora.safetensors"   # kebab
LORA_UNDER="ip_adapter_faceid_plusv2_sdxl_lora.safetensors"   # underscore
LORA_TARGET="${SDXL_DIR}/${LORA_CANON}"

# Consolidate any copies into the canonical target
for cand in \
  "${LORAS_DIR}/${LORA_CANON}" \
  "${LORAS_DIR}/${LORA_UNDER}" \
  "${IP_DIR}/${LORA_CANON}" \
  "${IP_DIR}/${LORA_UNDER}" \
  "${SDXL_DIR}/${LORA_UNDER}" \
  "${SDXL_DIR}/${LORA_CANON}"
do
  [ -e "$cand" ] && safe_move "$cand" "${LORA_TARGET}"
done

# Expose both spellings in loras/ as symlinks to the canonical target
if [ -s "${LORA_TARGET}" ]; then
  ln -sfn "${LORA_TARGET}" "${LORAS_DIR}/${LORA_CANON}"
  ln -sfn "${LORA_CANON}"  "${LORAS_DIR}/${LORA_UNDER}"
  ok "Linked LoRA aliases in loras/ -> ${LORA_TARGET}"
else
  warn "LoRA missing: ${LORA_TARGET} — the workflow may error 'LoRA model not found'."
fi

# Final sanity
if ! compgen -G "${SDXL_DIR}/ip_adapter_faceid_plusv2_sdxl.*" > /dev/null; then
  warn "IP-Adapter base (SDXL) not found in ${SDXL_DIR}."
fi

say "IP-Adapter FaceID v2 & LoRA paths normalized."

say "Fetching ControlNet: Flux-Union-Pro2.safetensors -> controlnet/"
hf_fetch "simwalo/FluxDevFP8" "dataset" "Flux-Union-Pro2.safetensors" "${CONTROLNET_DIR}" 0

# ⬇️ Add these two lines here
say "Fetching ControlNet: Flux1-controlnet-upscaler-Jasperai-fp8.safetensors -> controlnet/"
hf_fetch "simwalo/FluxDevFP8" "dataset" "Flux1-controlnet-upscaler-Jasperai-fp8.safetensors" "${CONTROLNET_DIR}" 0

###############################################################################
# IP-Adapter FaceID Plus v2 (SDXL) — wiring & aliases
###############################################################################
hdr "IP-Adapter FaceID Plus v2 (SDXL) wiring"
IP_DIR="${MODELS_DIR}/ipadapter"
LORA_DIR="${MODELS_DIR}/loras"
CLIPV_DIR="${MODELS_DIR}/clip_vision"
mkdir -p "${IP_DIR}/sdxl_models" "${LORA_DIR}" "${CLIPV_DIR}"

# We expect the actual files to live here (as we arranged earlier):
LORA_SRC="${IP_DIR}/sdxl_models/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
BASE_BIN_HYP="${IP_DIR}/ip-adapter-faceid-plusv2_sdxl.bin"
BASE_BIN_UND="${IP_DIR}/ip_adapter_faceid_plusv2_sdxl.bin"

# If both hyphen/underscore variants of the base .bin don't exist, add an alias so either name works.
if [ -f "${BASE_BIN_HYP}" ] && [ ! -e "${BASE_BIN_UND}" ]; then
  ln -sfn "ip-adapter-faceid-plusv2_sdxl.bin" "${BASE_BIN_UND}"
elif [ -f "${BASE_BIN_UND}" ] && [ ! -e "${BASE_BIN_HYP}" ]; then
  ln -sfn "ip_adapter_faceid_plusv2_sdxl.bin" "${BASE_BIN_HYP}"
fi

# Create LoRA aliases into loras/ so both naming styles resolve in UIs/workflows.
if [ -f "${LORA_SRC}" ]; then
  ln -sfn "${LORA_SRC}" "${LORA_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
  # second alias points to the first (keeps a short relative link inside loras/)
  ln -sfn "ip-adapter-faceid-plusv2_sdxl_lora.safetensors" \
          "${LORA_DIR}/ip_adapter_faceid_plusv2_sdxl_lora.safetensors"
else
  warn "IP-Adapter LoRA not found at ${LORA_SRC}. Download step may be missing."
fi

# Ensure CLIP-ViT vision checkpoints are visible under clip_vision/ (some nodes look only there).
for ckpt in ViT-H-14-laion2B-s32B-b79K.bin ViT-L-14-laion2B-s32B-b82K.bin; do
  if [ -f "${MODELS_DIR}/clip/${ckpt}" ]; then
    ln -sfn "${MODELS_DIR}/clip/${ckpt}" "${CLIPV_DIR}/${ckpt}"
  fi
done

# Quick sanity printout
say "IP-Adapter / LoRA links:"
printf '  '; ls -l "${IP_DIR}"            2>/dev/null | sed 's/^/  /'
printf '  '; ls -l "${IP_DIR}/sdxl_models" 2>/dev/null | sed 's/^/  /'
printf '  '; ls -l "${LORA_DIR}"          2>/dev/null | sed 's/^/  /'
printf '  '; ls -l "${CLIPV_DIR}"         2>/dev/null | sed 's/^/  /'

# ── SigLIP for Joy Caption Two ─────────────────────────────────
hdr "SigLIP for Joy Caption Two"
SIGLIP_DIR="${CLIP_DIR}/siglip-so400m-patch14-384"
if [ ! -e "${SIGLIP_DIR}/pytorch_model.bin" ] && \
   [ ! -e "${SIGLIP_DIR}/model.safetensors" ] && \
   [ ! -e "${SIGLIP_DIR}/flax_model.msgpack" ] && \
   [ ! -e "${SIGLIP_DIR}/config.json" ]; then
  say "Fetching SigLIP: google/siglip-so400m-patch14-384 → clip/"
  mkdir -p "${SIGLIP_DIR}"
  python - <<PY
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="google/siglip-so400m-patch14-384",
    local_dir="${SIGLIP_DIR}",
    local_dir_use_symlinks=False,
    allow_patterns=["*.json","*.safetensors","*.bin","*.msgpack","*config*"]
)
print("OK SigLIP downloaded.")
PY
  ok "SigLIP ready at ${SIGLIP_DIR}"
else
  ok "SigLIP already present at ${SIGLIP_DIR}"
fi

# Optional JC2 patch check (no changes needed if it already uses SiglipVisionModel)
hdr "Patch Joy Caption Two (SiglipVisionModel)"
JC2_PY="$(grep -RIl --include='*.py' -e 'SiglipVisionModel' "${NODES_DIR}/Comfyui_JC2" 2>/dev/null || true)"
if [ -n "${JC2_PY}" ]; then
  ok "No patch needed for JC2 (SiglipVisionModel already referenced)."
else
  ok "No Joy Caption Two patch applied (files not found or signature not used)."
fi

# LoRAs
say "Fetching LoRA: Touch_of_Realism_SDXL_V2.safetensors -> loras/sdxl/"
hf_fetch "simwalo/SDXL" "model" "Touch_of_Realism_SDXL_V2.safetensors" "${LORAS_SDXL_DIR}" 0
say "Fetching LoRA: comfyui_portrait_lora64.safetensors -> loras/"
hf_fetch "simwalo/FluxDevFP8" "dataset" "comfyui_portrait_lora64.safetensors" "${LORAS_DIR}" 0

# ── Base SDXL + VAE + CLIP (generic) ───────────────────────────
hdr "Models"
mkdir -p "${CHK_DIR}" "${VAE_DIR}" "${CLIP_DIR}" "${CLIP_VI_DIR}"
say "Downloading SDXL base/refiner…"
fetch "${SDXL_BASE_URL}"     "${SDXL_BASE_NAME}"    "${CHK_DIR}"
fetch "${SDXL_REFINER_URL}"  "${SDXL_REFINER_NAME}" "${CHK_DIR}"

say "Downloading SDXL VAE (fp16 fix)…"
TMPDL="${VAE_DIR}/.${SDXL_VAE_OUT}.aria2.tmp"
if [ ! -f "${VAE_DIR}/${SDXL_VAE_OUT}" ]; then
  retry 6 8 -- aria2c -x16 -s16 -k1M -o "$(basename "${TMPDL}")" -d "${VAE_DIR}" "${SDXL_VAE_URL}"
  mv -f "${VAE_DIR}/$(basename "${TMPDL}")" "${VAE_DIR}/${SDXL_VAE_OUT}" 2>/dev/null || true
fi
ok "VAE ready."

# Flux VAE (for Flux/FP8 workflows)
say "Fetching Flux VAE: ae.safetensors"
hf_fetch "simwalo/FluxDevFP8" "dataset" "ae.safetensors" "${VAE_DIR}" 0

say "Downloading CLIP weights (LAION)…"
fetch "${CLIP_L14_URL}" "${CLIP_L14_OUT}" "${CLIP_DIR}"
fetch "${CLIP_H14_URL}" "${CLIP_H14_OUT}" "${CLIP_DIR}"
# Mirror into clip_vision for nodes that expect that layout
ensure_dir_and_link "${CLIP_DIR}/${CLIP_L14_OUT}" "${CLIP_VI_DIR}" "${CLIP_L14_OUT}"
ensure_dir_and_link "${CLIP_DIR}/${CLIP_H14_OUT}" "${CLIP_VI_DIR}" "${CLIP_H14_OUT}"
ok "CLIP weights ready (also linked to clip_vision)."

# ── IP-Adapter FaceID+v2 (SDXL) ────────────────────────────────
hdr "IP-Adapter FaceID+v2 (SDXL)"
mkdir -p "${IPADAPTER_SDXL_DIR}" "${IPADAPTER_DIR}"

# 1) Download the FaceID+v2 .bin (model) and the SDXL LoRA (.safetensors)
python - "$IPADAPTER_SDXL_DIR" <<'PY'
import os, sys
from huggingface_hub import hf_hub_download, list_repo_files
td = sys.argv[1]; os.makedirs(td, exist_ok=True)

# Model .bin
bin_name = "ip-adapter-faceid-plusv2_sdxl.bin"
p_bin = hf_hub_download("h94/IP-Adapter-FaceID", filename=bin_name, repo_type="model",
                        local_dir=td, local_dir_use_symlinks=False, resume_download=True)
print("OK model:", p_bin)

# Try both common LoRA names
candidates = ["ip-adapter-faceid-plusv2_sdxl_lora.safetensors",
              "ip-adapter-faceid-plusv2_sdxl.safetensors"]
p_lora = None
for fn in candidates:
    try:
        p_lora = hf_hub_download("h94/IP-Adapter-FaceID", filename=fn, repo_type="model",
                                 local_dir=td, local_dir_use_symlinks=False, resume_download=True)
        print("OK lora :", p_lora)
        break
    except Exception as e:
        print("Missed", fn, "->", type(e).__name__, e)

if p_lora is None:
    # scan repo for any SDXL safetensors variant
    try:
        for fn in list_repo_files("h94/IP-Adapter-FaceID", repo_type="model"):
            if "sdxl" in fn and fn.endswith(".safetensors") and "faceid-plusv2" in fn:
                p_lora = hf_hub_download("h94/IP-Adapter-FaceID", filename=fn, repo_type="model",
                                         local_dir=td, local_dir_use_symlinks=False, resume_download=True)
                print("OK lora (fallback):", p_lora)
                break
    except Exception as e:
        print("List failed:", e)

if p_lora is None:
    raise SystemExit("ERROR: Could not download FaceID+v2 SDXL LoRA.")
PY

# 2) Present the files in ALL names the loader might ask for (no symlinks → copies)
IP_SDXL_DIR="${IPADAPTER_SDXL_DIR}"
IP_ROOT_DIR="${IPADAPTER_DIR}"
MODEL_SRC="${IP_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl.bin"

# Resolve LoRA filename (with or without _lora)
if   [ -f "${IP_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" ]; then
  LORA_SRC="${IP_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
elif [ -f "${IP_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors" ]; then
  LORA_SRC="${IP_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors"
else
  die "FaceID+v2 SDXL LoRA not found after download."
fi

# Copy (not link) to flat ipadapter/ with multiple expected names
safe_copy "${MODEL_SRC}" "${IP_ROOT_DIR}/ip-adapter-faceid-plusv2_sdxl.bin"
safe_copy "${MODEL_SRC}" "${IP_ROOT_DIR}/ip_adapter_faceid_plusv2_sdxl.bin" 2>/dev/null || true

safe_copy "${LORA_SRC}" "${IP_ROOT_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
safe_copy "${LORA_SRC}" "${IP_ROOT_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors"          # name w/o _lora
safe_copy "${LORA_SRC}" "${IP_ROOT_DIR}/ip_adapter_faceid_plusv2_sdxl_lora.safetensors" 2>/dev/null || true

echo "IP-Adapter flat dir contents:"
ls -lh "${IP_ROOT_DIR}" | grep -E 'faceid-plusv2.*(safetensors|bin)' || true
ok "FaceID+v2: model + LoRA laid out for “IPAdapterPlus” loader."

# --- FaceID+v2 hardening: add every filename variant the loader might request
hdr "FaceID+v2 hardening (LoRA discoverability)"

IP_ROOT_DIR="/workspace/ComfyUI/models/ipadapter"
IP_SDXL_DIR="/workspace/ComfyUI/models/ipadapter/sdxl_models"

mkdir -p "$IP_ROOT_DIR" "$IP_SDXL_DIR"

# Ensure the real files are present in the flat ipadapter/ root
[ -f "$IP_ROOT_DIR/ip-adapter-faceid-plusv2_sdxl.bin" ] || cp -f \
  "$IP_SDXL_DIR/ip-adapter-faceid-plusv2_sdxl.bin" "$IP_ROOT_DIR/"

LORA_CANON=""
if   [ -f "$IP_SDXL_DIR/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" ]; then
  LORA_CANON="ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
elif [ -f "$IP_SDXL_DIR/ip-adapter-faceid-plusv2_sdxl.safetensors" ]; then
  LORA_CANON="ip-adapter-faceid-plusv2_sdxl.safetensors"
fi
if [ -n "$LORA_CANON" ] && [ ! -f "$IP_ROOT_DIR/$LORA_CANON" ]; then
  cp -f "$IP_SDXL_DIR/$LORA_CANON" "$IP_ROOT_DIR/"
fi

cd "$IP_ROOT_DIR"

# Helper: try symlink first, copy if filesystem forbids links
_alias() {
  local src="$1" dst="$2"
  [ -e "$dst" ] && return 0
  ln -s "$src" "$dst" 2>/dev/null || cp -f "$src" "$dst"
}

# LoRA variants (with/without _lora, hyphen/underscore, dropped hyphen after 'ip')
if [ -f "ip-adapter-faceid-plusv2_sdxl_lora.safetensors" ]; then
  for n in \
    ip-adapter-faceid-plusv2_sdxl.safetensors \
    ip_adapter_faceid_plusv2_sdxl_lora.safetensors \
    ip_adapter_faceid_plusv2_sdxl.safetensors \
    ipadapter-faceid-plusv2_sdxl.safetensors \
    ipadapter_faceid_plusv2_sdxl.safetensors
  do _alias ip-adapter-faceid-plusv2_sdxl_lora.safetensors "$n"; done
elif [ -f "ip-adapter-faceid-plusv2_sdxl.safetensors" ]; then
  for n in \
    ip-adapter-faceid-plusv2_sdxl_lora.safetensors \
    ip_adapter_faceid_plusv2_sdxl_lora.safetensors \
    ip_adapter_faceid_plusv2_sdxl.safetensors \
    ipadapter-faceid-plusv2_sdxl.safetensors \
    ipadapter_faceid_plusv2_sdxl.safetensors
  do _alias ip-adapter-faceid-plusv2_sdxl.safetensors "$n"; done
fi

# BIN variants
if [ -f "ip-adapter-faceid-plusv2_sdxl.bin" ]; then
  for n in \
    ip_adapter_faceid_plusv2_sdxl.bin \
    ipadapter-faceid-plusv2_sdxl.bin \
    ipadapter_faceid_plusv2_sdxl.bin
  do _alias ip-adapter-faceid-plusv2_sdxl.bin "$n"; done
fi

echo "IP-Adapter files (post-hardening):"
ls -lh | grep -E 'faceid[-_]?plusv2.*sdxl.*(bin|safetensors)' || true

# ── LoRA discoverability shims (Power LoRA Loader friendly) ────
# Some loaders (e.g. rgthree Power LoRA Loader) log paths like:
#   "sdxl\Touch_of_Realism_SDXL_V2.safetensors"
# On Linux, the backslash "\" is a normal character, not a separator,
# so the file won't be found unless we add aliases in loras/.
#
# This block:
#  1) exposes SDXL LoRAs at loras/ (no subdir), and
#  2) adds a second alias named literally "sdxl\<name>.safetensors"
#     to match Windows-style inputs that some nodes emit.
#
# If symlinks aren't allowed, it falls back to copying.

hdr "LoRA discoverability shims"
mkdir -p "${LORAS_DIR}" "${LORAS_SDXL_DIR}"

expose_lora() {
  local src="$1"
  local base="$(basename "$src")"
  local dst1="${LORAS_DIR}/${base}"                   # loras/<name>.safetensors
  local dst2="${LORAS_DIR}/sdxl\\${base}"            # loras/sdxl\<name>.safetensors (backslash literal)
  local dst3="${LORAS_DIR}/sdxl/${base}"             # loras/sdxl/<name>.safetensors (forward-slash subdir)

  # Make/base alias in loras/
  if [ ! -e "$dst1" ]; then
    ln -s "$src" "$dst1" 2>/dev/null || cp -f "$src" "$dst1"
    ok "Exposed LoRA at: ${dst1}"
  else
    ok "LoRA alias already exists: ${dst1}"
  fi

  # Backslash filename alias
  if [ ! -e "$dst2" ]; then
    ln -s "$src" "$dst2" 2>/dev/null || cp -f "$src" "$dst2"
    ok "Added Windows-style alias: ${dst2}"
  else
    ok "Windows-style alias already exists: ${dst2}"
  fi

  # Forward-slash subfolder alias
  mkdir -p "${LORAS_DIR}/sdxl"
  if [ ! -e "$dst3" ]; then
    ln -s "$src" "$dst3" 2>/dev/null || cp -f "$src" "$dst3"
    ok "Added forward-slash alias: ${dst3}"
  else
    ok "Forward-slash alias already exists: ${dst3}"
  fi
}

# Apply to Touch of Realism (and any other SDXL LoRAs you drop in)
if ls "${LORAS_SDXL_DIR}"/*.safetensors >/dev/null 2>&1; then
  for f in "${LORAS_SDXL_DIR}"/*.safetensors; do
    [ -f "$f" ] || continue
    expose_lora "$f"
  done
else
  warn "No SDXL LoRAs found in ${LORAS_SDXL_DIR}; nothing to expose."
fi

# ── IP-Adapter FaceID+v2 aliases (flat root) ───────────────────
hdr "IP-Adapter FaceID+v2 aliases (flat root)"
IP_SDXL_BIN="${IPADAPTER_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl.bin"

# Resolve actual LoRA filename (some releases omit "_lora")
if [ -f "${IPADAPTER_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" ]; then
  IP_SDXL_LORA="${IPADAPTER_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"
elif [ -f "${IPADAPTER_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors" ]; then
  IP_SDXL_LORA="${IPADAPTER_SDXL_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors"
else
  warn "FaceID+v2 SDXL LoRA not found in ${IPADAPTER_SDXL_DIR}"
  IP_SDXL_LORA=""
fi

mkdir -p "${IPADAPTER_DIR}"

# Helper: link or copy if symlinks aren’t allowed
_make_alias() {
  local src="$1" dst="$2"
  [ -z "$src" ] && return 0
  [ ! -e "$src" ] && { warn "Source missing for alias: $src"; return 0; }
  ln -sfn "$src" "$dst" 2>/dev/null || cp -f "$src" "$dst"
  ok "Aliased $(basename "$src") → $(basename "$dst")"
}

# Put canonical names in ipadapter/
_make_alias "${IP_SDXL_BIN}"  "${IPADAPTER_DIR}/ip-adapter-faceid-plusv2_sdxl.bin"
_make_alias "${IP_SDXL_LORA}" "${IPADAPTER_DIR}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"

# (Optional) Extra friendly names some graphs expect
_make_alias "${IP_SDXL_LORA}" "${IPADAPTER_DIR}/ip-adapter-faceid-plusv2_sdxl.safetensors"        # without "_lora"
_make_alias "${IP_SDXL_BIN}"  "${IPADAPTER_DIR}/ip_adapter_faceid_plusv2_sdxl.bin"                 # underscores variant
_make_alias "${IP_SDXL_LORA}" "${IPADAPTER_DIR}/ip_adapter_faceid_plusv2_sdxl_lora.safetensors"    # underscores variant

# === Canonicalize & scrub so only the two exact names remain ===
IPROOT="${IPADAPTER_DIR}"
IPSDXL="${IPADAPTER_SDXL_DIR}"

# Remove every FaceID+v2 SDXL variant in ipadapter/ EXCEPT the two canonical names
#   keep:  ip-adapter-faceid-plusv2_sdxl.bin
#          ip-adapter-faceid-plusv2_sdxl_lora.safetensors
find "$IPROOT" -maxdepth 1 \( -type f -o -type l \) -regextype posix-extended \
  -regex '.*/(ip-?adapter[_-]?faceid[_-]?plusv2[_-]?sdxl.*\.(bin|safetensors))' \
  ! -name 'ip-adapter-faceid-plusv2_sdxl.bin' \
  ! -name 'ip-adapter-faceid-plusv2_sdxl_lora.safetensors' \
  -print -delete || true

# Recreate the two canonical links to the real files in sdxl_models (in case they were removed above)
ln -sfn "${IPSDXL}/ip-adapter-faceid-plusv2_sdxl.bin" \
        "${IPROOT}/ip-adapter-faceid-plusv2_sdxl.bin" 2>/dev/null || cp -f "${IPSDXL}/ip-adapter-faceid-plusv2_sdxl.bin" "${IPROOT}/"
[ -n "${IP_SDXL_LORA}" ] && ln -sfn "${IP_SDXL_LORA}" \
        "${IPROOT}/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" 2>/dev/null || { [ -n "${IP_SDXL_LORA}" ] && cp -f "${IP_SDXL_LORA}" "${IPROOT}/"; }

# Clean any dangling symlinks (defensive)
find "$IPROOT" -maxdepth 1 -type l ! -exec test -e {} \; -print -delete || true

# Debug: show what the loader will see
echo "IP-Adapter flat dir contents (should be exactly two lines below):"
ls -l "${IPROOT}" | sed -n '/faceid.*sdxl/p'

# ── Upscaler models ────────────────────────────────────────────
hdr "Upscaler models"
mkdir -p "${UPSCALE_DIR}"

say "Fetching 4x-ClearRealityV1.pth"
fetch "https://huggingface.co/skbhadra/ClearRealityV1/resolve/main/4x-ClearRealityV1.pth" \
      "4x-ClearRealityV1.pth" "${UPSCALE_DIR}"
ok "ClearReality upscaler ready at ${UPSCALE_DIR}/4x-ClearRealityV1.pth"

say "Fetching RealESRGAN_x2plus.pth"
fetch "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth" \
      "RealESRGAN_x2plus.pth" "${UPSCALE_DIR}"
ok "RealESRGAN_x2plus ready at ${UPSCALE_DIR}/RealESRGAN_x2plus.pth"

# ── IP-Adapter quick sanity check (non-fatal) ──────────────────
python - <<'PY'
import os
try:
    import torch
    from safetensors import safe_open
except Exception as e:
    print("Sanity check skipped (imports failed):", e)
    raise SystemExit(0)

base = "/workspace/ComfyUI/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin"
print("Base .bin exists:", os.path.exists(base))
try:
    if os.path.exists(base):
        _ = torch.load(base, map_location="cpu")
        print("torch.load(.bin): OK")
except Exception as e:
    print("WARN torch.load(.bin) failed:", e)

td = "/workspace/ComfyUI/models/ipadapter"
try:
    loras = [f for f in os.listdir(td) if f.endswith(".safetensors")]
    print("Found LoRAs:", loras[:5], "…" if len(loras) > 5 else "")
    if loras:
        p = os.path.join(td, loras[0])
        with safe_open(p, framework="pt", device="cpu") as f:
            print("safetensors header keys sample:", list(f.keys())[:3])
except Exception as e:
    print("WARN safetensors open failed:", e)
PY

###############################################################################
# SDXL NSFW V2 – runtime fix pack (deps + node quirks)
# Put this AFTER model/custom-node downloads, BEFORE starting ComfyUI.
###############################################################################
(
set -euo pipefail
PY="/workspace/miniconda3/envs/comfyui/bin/python"
PIP="$PY -m pip"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Fix pack: Python deps (lightweight; keep Torch/CUDA as-is)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
(
set -euo pipefail
PY="/workspace/miniconda3/envs/comfyui/bin/python"
PIP="$PY -m pip"

# Make pip predictable & fast
export PIP_NO_INPUT=1 PIP_DEFAULT_TIMEOUT=240 PIP_PREFER_BINARY=1

# 0) Show the Torch we already have (we WON'T touch it)
$PY - <<'PY'
try:
    import torch
    print("Torch present:", torch.__version__)
except Exception as e:
    print("Torch check failed (will still skip reinstall):", e)
PY

# 1) Remove only the packages we want to replace (DO NOT touch torch/nvidia wheels)
$PY - <<'PY'
import sys, subprocess
pkgs = [
  "transformers","diffusers","peft","tokenizers",
  "huggingface_hub","hf-xet",
  "opencv-python","opencv-python-headless","opencv-contrib-python","opencv-contrib-python-headless",
  "protobuf","numpy",
  "tqdm","requests","regex","pyyaml","packaging","pillow","importlib-metadata","fsspec","typing-extensions","filelock"
]
for p in pkgs:
    subprocess.call([sys.executable,"-m","pip","uninstall","-y",p], stdout=subprocess.DEVNULL)
print("Uninstall pass done (torch left intact).")
PY

# 2) Install known-good user-space libs (NO deps so we don't drag Torch)
#    Pin what we use so resolver doesn't try to modify torch.
$PIP install --no-cache-dir --no-deps -U \
  "transformers==4.56.1" \
  "tokenizers==0.22.0" \
  "diffusers==0.35.1" \
  "peft>=0.17.1" \
  "accelerate>=0.33" \
  "protobuf>=4.25.3,<5" \
  "numpy==2.2.6" \
  "huggingface-hub==0.34.5" \
  "requests==2.32.5" \
  "tqdm==4.67.1" \
  "regex==2025.9.1" \
  "pyyaml==6.0.2" \
  "packaging==25.0" \
  "pillow==11.3.0" \
  "importlib_metadata==8.7.0" \
  "fsspec==2025.9.0" \
  "typing-extensions==4.15.0" \
  "filelock==3.19.1" \
  "hf-xet==1.1.10"

# 3) OpenCV: force headless-contrib (needed for ximgproc/guidedFilter)
$PIP uninstall -y opencv-python opencv-contrib-python opencv-python-headless opencv-contrib-python-headless >/dev/null 2>&1 || true
$PIP install --no-cache-dir -U "opencv-contrib-python-headless==4.12.0.88"

# 4) Transformers 'arcee' shim (some older nodes import it)
$PY - <<'PY'
import importlib.util, pathlib, sys
try:
    import transformers
    root = pathlib.Path(transformers.__file__).parent
    arcee_dir = root / "models" / "arcee"
    if importlib.util.find_spec("transformers.models.arcee") is None:
        arcee_dir.mkdir(parents=True, exist_ok=True)
        (arcee_dir / "__init__.py").write_text("# shim module for older Transformers builds\n")
        print("Created shim:", arcee_dir)
    else:
        print("arcee already present")
except Exception as e:
    print("Transformers import/shim failed:", e)
PY

# 5) Sanity print (ensures everything is importable without touching Torch)
$PY - <<'PY'
import cv2, transformers, tokenizers, diffusers, peft, numpy
print("transformers:", transformers.__version__)
print("tokenizers:", tokenizers.__version__)
print("diffusers:", diffusers.__version__)
print("peft:", peft.__version__)
print("numpy:", numpy.__version__)
print("cv2:", cv2.__version__, "ximgproc:", hasattr(cv2, "ximgproc"))
PY

# 6) Verify pip env consistency
$PIP check || true
)
echo "Python deps fix pack done."

# Optional: ffmpeg (some nodes shell out to it)
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Installing ffmpeg (apt)…"
  apt-get update -y && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
fi

# ONNX + InsightFace (GPU first, CPU fallback)
python -m pip install --no-cache-dir -U "onnx==1.16.2"
python -m pip install --no-cache-dir -U "onnxruntime-gpu==1.19.2" \
  || python -m pip install --no-cache-dir -U "onnxruntime==1.19.2"

# InsightFace (uses onnxruntime)
python -m pip install --no-cache-dir -U "insightface"

# Quick probe so logs clearly show the device
python - <<'PY'
import onnxruntime as ort, insightface
print("[probe] onnxruntime device:", ort.get_device())
print("[probe] insightface:", insightface.__version__)
PY

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Fix pack: prune problematic custom_nodes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
find /workspace/ComfyUI/custom_nodes -type d -name ".ipynb_checkpoints" -prune -exec rm -rf {} + || true
rm -rf /workspace/ComfyUI/custom_nodes/alias_florence_saver || true

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Fix pack: optional Comfyroll Upscale whitelist"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CR_NODE_FILE="$(grep -RIl 'class .*CR.*Upscale' /workspace/ComfyUI/custom_nodes/ComfyUI_Comfyroll_CustomNodes 2>/dev/null || true)"
if [ -n "${CR_NODE_FILE}" ] && ! grep -q '4x-ClearRealityV1.pth' "${CR_NODE_FILE}"; then
  sed -i 's/"RealESRGAN_x2plus\.pth"/"RealESRGAN_x2plus.pth","4x-ClearRealityV1.pth"/' "${CR_NODE_FILE}" || true
  echo "Patched Comfyroll Upscale node to allow 4x-ClearRealityV1.pth."
else
  echo "Comfyroll Upscale node patch not needed or file not found; skipping."
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Fix pack: clean pyc/caches"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
find /workspace/ComfyUI -type d -name "__pycache__" -prune -exec rm -rf {} + || true
find /workspace/ComfyUI -type f -name "*.pyc" -delete || true

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Fix pack: quick sanity check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
$PY - <<'PY'
import cv2, transformers, diffusers, peft
print("transformers:", transformers.__version__)
print("diffusers:", diffusers.__version__)
print("peft:", peft.__version__)
print("opencv ximgproc present:", hasattr(cv2, "ximgproc"))
PY
echo "Fix pack done."
)

# Fix pack subshell… (after conda activate)
(
  set -euo pipefail
  # you can still reference $PY, but the helpers already use $PY_BIN
  export PIP_NO_INPUT=1 PIP_DEFAULT_TIMEOUT=240 PIP_PREFER_BINARY=1 PIP_DISABLE_PIP_VERSION_CHECK=1
  quiet_pip "Pin packaging" -- install --no-cache-dir -U "packaging>=25"
  # example 
  # ...
)

# ONNX stack (after fix pack)
quiet_pip "Uninstall ONNX stack" -- uninstall -y onnxruntime-gpu onnxruntime onnx || true
if ! quiet_pip "Install ONNX (GPU)" -- install --no-cache-dir -U "onnx==1.16.2" "onnxruntime-gpu==1.19.2"; then
  warn "onnxruntime-gpu not available; falling back to CPU onnxruntime"
  quiet_pip "Install ONNX (CPU)" -- install --no-cache-dir -U "onnx==1.16.2" "onnxruntime==1.19.2" || warn "onnx/onnxruntime install failed"
fi

# Final polish OpenCV/Mediapipe (after ONNX)
quiet_pip "OpenCV cleanup" -- uninstall -y opencv-python opencv-python-headless opencv-contrib-python || true
quiet_pip "OpenCV headless (contrib)" -- install --no-cache-dir -U "opencv-contrib-python-headless==4.12.0.88"

python - <<'PY'
import subprocess, sys
# Try 0.10.20 first, fall back to 0.10.14 (both are NumPy 2–compatible)
for ver in ("0.10.20","0.10.18","0.10.14"):
    rc = subprocess.call([sys.executable,"-m","pip","install","--no-cache-dir",f"mediapipe=={ver}"])
    if rc == 0:
        print("mediapipe pinned to", ver)
        break
PY

###############################################################################
# Final polish: align OpenCV + Mediapipe (post-fix-pack, pre-Finish)
###############################################################################
hdr "Final polish: OpenCV + Mediapipe"
# Ensure we're in the right env (no-op if already active)
if [ -f "${WORKDIR}/miniconda3/etc/profile.d/conda.sh" ]; then
  . "${WORKDIR}/miniconda3/etc/profile.d/conda.sh"
  conda activate "${CONDA_ENV_NAME}" >/dev/null 2>&1 || true
fi

# Reassert a single OpenCV provider (contrib-headless has ximgproc & friends)
python -m pip uninstall -y opencv-python opencv-python-headless opencv-contrib-python >/dev/null 2>&1 || true
python -m pip install --no-cache-dir -U "opencv-contrib-python-headless==4.12.0.88"

# Keep mediapipe on a build that’s happy with NumPy 2.x and our OpenCV
python - <<'PY'
import subprocess, sys
for ver in ("0.10.20","0.10.18","0.10.14"):
    rc = subprocess.call([sys.executable,"-m","pip","install","--no-cache-dir",f"mediapipe=={ver}"])
    if rc == 0:
        print("mediapipe pinned to", ver)
        break
PY

# Quick import check
python - <<'PY'
import numpy, cv2, mediapipe
print("numpy:", numpy.__version__)
print("opencv:", cv2.__version__, "ximgproc?", hasattr(cv2, "ximgproc"))
print("mediapipe:", mediapipe.__version__)
PY

GUARD_NODE_DIR="${NODES_DIR}/_class_type_guard"
mkdir -p "${GUARD_NODE_DIR}"
cat > "${GUARD_NODE_DIR}/__init__.py" <<'PY'
WEB_DIRECTORY = None
def pre_execute(prompt):
    try:
        nodes = []
        if isinstance(prompt, dict):
            if isinstance(prompt.get("nodes"), list):
                nodes = prompt["nodes"]
            else:
                try: nodes = list(prompt.values())
                except Exception: nodes = []
        patched = 0
        for n in nodes:
            if isinstance(n, dict) and "class_type" not in n and "type" in n:
                n["class_type"] = n["type"]; patched += 1
        if patched:
            print(f"[class_type_guard] patched {patched} node(s).")
        return prompt
    except Exception as e:
        print("[class_type_guard] failed:", e); return prompt
PY
ok "Installed server-side class_type guard"

###############################################################################
# Workflow guard: add class_type if missing (client-side, before queue)
###############################################################################
hdr "Workflow guard: add class_type if missing (web extension)"
EXT_DIR="${COMFY_DIR}/web/extensions"
mkdir -p "${EXT_DIR}"

cat > "${EXT_DIR}/10-fix-missing-class_type.js" <<'JS'
// Adds class_type to nodes that only have `type`.
// Works for queueing prompts from the UI and API calls sent via the web app.
app.registerExtension({
  name: "fix-missing-class-type",
  beforeQueuePrompt: async (data) => {
    try {
      const p = data?.prompt;
      if (p?.nodes && Array.isArray(p.nodes)) {
        for (const n of p.nodes) {
          if (n && !n.class_type && n.type) n.class_type = n.type;
        }
      }
    } catch (e) {
      console.warn("[fix-missing-class-type] failed:", e);
    }
    return data;
  },
});
JS

ok "Installed web extension: web/extensions/10-fix-missing-class_type.js"

################################################################################
# Finish
################################################################################
hdr "Finish"
banner_bottom
ok " All set!    Launch ComfyUI with the startup command:    ./Run_Comfyui.sh"
printf "               Check out my other tools in github:   https://github.com/CryptoAce85\n"
printf '%b' "$YELLOW"
printf '                                Made with 💖  by 🐺  CryptoAce85 🐺\n'
printf '%b' "$RESET"
sleep 0.1
