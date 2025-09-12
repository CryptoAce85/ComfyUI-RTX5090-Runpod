#!/bin/bash
# Adapted ComfyUI setup with Conda for RTX 5090 on RunPod
echo "
========================================
🚀 Starting ComfyUI setup with Conda...
========================================
"

# Create base directories
echo "
----------------------------------------
📁 Creating base directories...
----------------------------------------"
mkdir -p /workspace/ComfyUI
rm -rf /workspace/miniconda3  # Force fresh install
mkdir -p /workspace/miniconda3

# Download and install Miniconda
echo "
----------------------------------------
📥 Downloading and installing Miniconda...
----------------------------------------"
cd /workspace/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -p /workspace/miniconda3 -f
rm -f Miniconda3-latest-Linux-x86_64.sh

# Initialize conda in the shell using eval
echo "
----------------------------------------
🐍 Initializing conda...
----------------------------------------"
eval "$(/workspace/miniconda3/bin/conda shell.bash hook)"

# Accept Terms of Service for required channels
echo "
----------------------------------------
📝 Accepting Terms of Service for Conda channels...
----------------------------------------"
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Clone or update ComfyUI
echo "
----------------------------------------
📥 Cloning ComfyUI repository...
----------------------------------------"
if [ ! -d "/workspace/ComfyUI/.git" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
else
    echo "ComfyUI already exists, updating..."
    cd /workspace/ComfyUI
    git fetch origin
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || echo "Warning: Failed to checkout a valid branch"
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "Warning: Failed to update ComfyUI"
    cd /workspace
fi

# Create conda environment with Python 3.10
echo "
----------------------------------------
🌟 Creating conda environment...
----------------------------------------"
if ! conda info --envs | grep -q "comfyui"; then
    conda create -n comfyui python=3.10 -y
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create comfyui environment"
        exit 1
    fi
else
    echo "comfyui environment already exists, skipping creation..."
fi

# Activate conda environment
echo "
----------------------------------------
🔧 Activating comfyui environment...
----------------------------------------"
set -x # Enable debug mode
conda activate comfyui
if [ "$CONDA_DEFAULT_ENV" != "comfyui" ]; then
    echo "❌ Failed to activate comfyui environment! Current env: $CONDA_DEFAULT_ENV"
    exit 1
fi
echo "✅ Successfully activated comfyui environment"

# Install PyTorch and dependencies
cd /workspace/ComfyUI
echo "
----------------------------------------
📦 Installing PyTorch and dependencies...
----------------------------------------"
conda install pytorch==2.8.0 torchvision==0.23.0 torchaudio==2.6.0 cudatoolkit=12.8 -c pytorch -c nvidia -y
if [ $? -ne 0 ]; then
    echo "❌ Failed to install PyTorch and dependencies with Conda, trying pip..."
    pip install torch==2.8.0+cu128 torchvision==0.23.0+cu128 torchaudio==2.6.0+cu128 --index-url https://download.pytorch.org/whl/cu128
fi
pip install -r requirements.txt
pip install onnxruntime-gpu accelerate diffusers transformers mediapipe>=0.10.8 omegaconf einops opencv-python==4.11.0.86 face-alignment decord ffmpeg-python>=0.2.0 safetensors soundfile pytorch-lightning scipy librosa resampy kornia

# Install custom nodes
echo "
----------------------------------------
📥 Installing custom nodes...
----------------------------------------"
mkdir -p /workspace/ComfyUI/custom_nodes
cd /workspace/ComfyUI/custom_nodes
declare -a repos=(
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/kijai/ComfyUI-Florence2"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/ltdrdata/ComfyUI-Inspire-Pack"
    "https://github.com/jamesWalker55/comfyui-various"
    "https://github.com/un-seen/comfyui-tensorops"
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/PowerHouseMan/ComfyUI-AdvancedLivePortrait"
    "https://github.com/cubiq/ComfyUI_FaceAnalysis"
    "https://github.com/BadCafeCode/masquerade-nodes-comfyui"
    "https://github.com/Ryuukeisyou/comfyui_face_parsing"
    "https://github.com/TinyTerra/ComfyUI_tinyterraNodes"
    "https://github.com/Pixelailabs/Save_Florence2_Bulk_Prompts"
    "https://github.com/chflame163/ComfyUI_LayerStyle_Advance"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation"
    "https://github.com/orssorbit/ComfyUI-wanBlockswap"
    "https://github.com/1038lab/ComfyUI-SparkTTS"
    "https://github.com/EvilBT/ComfyUI_SLK_joy_caption_two"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/christian-byrne/audio-separation-nodes-comfyui"
    "https://github.com/Comfy-Org/ComfyUI-Manager"
    "https://github.com/MoonGoblinDev/Civicomfy"
    "https://github.com/vrgamegirl19/comfyui-vrgamedevgirl"
    "https://github.com/ClownsharkBatwing/RES4LYF"
    "https://github.com/WASasquatch/was-node-suite-comfyui"
    "https://github.com/crystian/ComfyUI-Crystools"
)

for repo in "${repos[@]}"; do
    repo_name=$(basename "$repo" .git)
    echo "Processing $repo_name..."
    if [ -d "$repo_name" ]; then
        echo "$repo_name exists, updating..."
        cd "$repo_name"
        if [[ "$repo_name" == "ComfyUI_SLK_joy_caption_two" ]]; then
            git pull origin master 2>/dev/null || echo "Warning: Failed to update $repo_name"
        else
            git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "Warning: Failed to update $repo_name"
        fi
        cd ..
    else
        echo "Cloning $repo_name..."
        git clone "$repo" || echo "Warning: Failed to clone $repo_name"
    fi
    if [ -d "$repo_name" ] && [ "$repo_name" == "ComfyUI-Easy-Use" ]; then
        cd "$repo_name"
        git checkout tags/v1.3.3
        if [ -f "requirements.txt" ]; then
            echo "Installing requirements for $repo_name..."
            pip install -r requirements.txt || echo "Warning: Failed to install requirements"
        fi
        cd ..
    elif [ -d "$repo_name" ]; then
        cd "$repo_name"
        if [ -f "requirements.txt" ]; then
            echo "Installing requirements for $repo_name..."
            if [[ "$repo_name" == "ComfyUI_SLK_joy_caption_two" ]]; then
                grep -v "huggingface_hub" requirements.txt > temp_requirements.txt 2>/dev/null || cp requirements.txt temp_requirements.txt
                pip install -r temp_requirements.txt || echo "Warning: Failed to install requirements"
                rm -f temp_requirements.txt
            else
                pip install -r requirements.txt || echo "Warning: Failed to install requirements"
            fi
        fi
        cd ..
    fi
done

# Configure WAS Node Suite for VRAM monitoring
WAS_CONFIG="/workspace/ComfyUI/custom_nodes/was-node-suite-comfyui/was_suite_config.json"
if [ -f "$WAS_CONFIG" ]; then
    if ! grep -q '"enable_vram_monitor": true' "$WAS_CONFIG"; then
        echo "Configuring WAS Node Suite for VRAM monitoring..."
        jq '.enable_vram_monitor = true' "$WAS_CONFIG" > tmp.json && mv tmp.json "$WAS_CONFIG" || echo "Warning: Failed to update WAS config"
    fi
    if ! grep -q '"vram_display_mode": "bars"' "$WAS_CONFIG"; then
        echo "Adding vram_display_mode to WAS config..."
        jq '. += {"vram_display_mode": "bars"}' "$WAS_CONFIG" > tmp.json && mv tmp.json "$WAS_CONFIG" || echo "Warning: Failed to add vram_display_mode"
    fi
else
    echo "Creating WAS Node Suite config with VRAM monitoring..."
    echo '{"enable_vram_monitor": true, "vram_display_mode": "bars"}' > "$WAS_CONFIG" || echo "Warning: Failed to create WAS config"
fi

# Deactivate conda environment
echo "
----------------------------------------
🔄 Deactivating comfyui environment...
----------------------------------------"
conda deactivate
set +x # Disable debug mode
echo "
========================================
✨ Setup complete! ✨
To start ComfyUI:
1. Run: /workspace/miniconda3/bin/conda init bash
2. Run: conda activate comfyui
3. Run: /workspace/Run_Comfyui.sh
========================================
Made with 💖  by 🐺  CryptoAce85 🐺
========================================
"