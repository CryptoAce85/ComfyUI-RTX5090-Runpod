#!/bin/bash
set -e
echo "=== ComfyUI Post-Restart Fixes ==="
check_system_deps() {
    echo "Checking system dependencies..."
    if [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
        SUDO_CMD=""
        if [ "$EUID" -ne 0 ]; then SUDO_CMD="sudo"; fi
        $SUDO_CMD ldconfig
        if ! dpkg -l | grep -q unzip; then
            $SUDO_CMD apt update -qq
            $SUDO_CMD apt install -y unzip
        fi
    fi
}
clean_problematic_files() {
    echo "Cleaning cache files..."
    rm -rf "/workspace/ComfyUI/custom_nodes/.cache"
    find /workspace/ComfyUI -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find /workspace/ComfyUI -name "*.pyc" -delete 2>/dev/null || true
    rm -rf ~/.triton/cache /tmp/latentsync_*
    mkdir -p ~/.triton/cache
}
fix_venv_issues() {
    echo "Checking Conda environment..."
    if [ ! -d "/workspace/miniconda3/envs/comfyui" ]; then echo "ERROR: Conda environment not found"; exit 1; fi
    source /workspace/miniconda3/etc/profile.d/conda.sh
    conda activate comfyui
    if [ "$CONDA_DEFAULT_ENV" != "comfyui" ]; then echo "ERROR: Conda activation failed"; exit 1; fi
    echo "Conda environment activated: $CONDA_DEFAULT_ENV"
}
set_optimal_env() {
    echo "Setting environment variables..."
    export CUDA_HOME=/usr/local/cuda-12.8
    export PATH=$CUDA_HOME/bin:$PATH
    export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
    export CFLAGS="-I/usr/include/python3.10"
    export CPPFLAGS="-I/usr/include/python3.10"
    export TORCH_DISABLE_SAFE_DESERIALIZER=1
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
    export TOKENIZERS_PARALLELISM=false
    export BITSANDBYTES_NOWELCOME=1
    export TRITON_CACHE_DIR=/tmp/triton_cache
    mkdir -p /tmp/triton_cache
}
main() {
    echo "🔧 Running post-restart fixes..."
    check_system_deps
    clean_problematic_files
    fix_venv_issues
    set_optimal_env
    cd /workspace/ComfyUI
    echo "✅  All fixes applied!"
    echo "🚀  Starting ComfyUI..."
    echo "Made with 💖  by 🐺  CryptoAce85 🐺"
    python main.py --fast --listen --disable-cuda-malloc
}
main