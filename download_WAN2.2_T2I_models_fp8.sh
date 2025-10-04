#!/bin/bash
set -e
echo "=== Downloading WAN2.2 T2I Models (FP8) and Installing Nodes ==="
# Ensure dependencies are installed
echo "🔧 Installing required system dependencies..."
apt update -qq && apt install -y unzip portaudio19-dev jq build-essential cmake python3-venv || { echo "❌ Failed to install unzip, portaudio, jq, build tools, or python3-venv"; exit 1; }
# Ensure directories exist
BASE_DOWNLOAD_DIR=/workspace/ComfyUI/models
mkdir -p "$BASE_DOWNLOAD_DIR/unet/T2V" "$BASE_DOWNLOAD_DIR/vae" "$BASE_DOWNLOAD_DIR/clip" "$BASE_DOWNLOAD_DIR/loras" "$BASE_DOWNLOAD_DIR/LLM"
# Install required custom nodes (including automated ComfyUI-Manager and Civicomfy installation)
echo "🔧 Installing custom nodes..."
cd /workspace/ComfyUI/custom_nodes || { echo "❌ Failed to change to custom_nodes directory"; exit 1; }
if [ ! -d "RES4LYF" ]; then
    echo "Cloning RES4LYF..."
    git clone https://github.com/ClownsharkBatwing/RES4LYF || { echo "❌ Failed to clone RES4LYF"; exit 1; }
    cd RES4LYF
    pip install -r requirements.txt || { echo "⚠️ Failed to install RES4LYF requirements, proceeding anyway"; cd ..; }
    cd ..
else
    echo "Updating RES4LYF..."
    cd RES4LYF
    git pull || { echo "⚠️ Failed to update RES4LYF, proceeding anyway"; cd ..; }
    cd ..
fi
if [ ! -d "was-node-suite-comfyui" ]; then
    echo "Cloning WAS Node Suite..."
    git clone https://github.com/WASasquatch/was-node-suite-comfyui || { echo "❌ Failed to clone WAS Node Suite"; exit 1; }
    cd was-node-suite-comfyui
    pip install -r requirements.txt psutil GPUtil || { echo "⚠️ Failed to install WAS Node Suite requirements, proceeding anyway"; cd ..; }
    cd ..
else
    echo "Updating WAS Node Suite..."
    cd was-node-suite-comfyui
    git pull || { echo "⚠️ Failed to update WAS Node Suite, proceeding anyway"; }
    pip install -r requirements.txt psutil GPUtil || { echo "⚠️ Failed to install WAS Node Suite requirements, proceeding anyway"; cd ..; }
    cd ..
fi
if [ ! -d "ComfyUI_tinyterraNodes" ]; then
    echo "Cloning ComfyUI_tinyterraNodes..."
    git clone https://github.com/TinyTerra/ComfyUI_tinyterraNodes || { echo "❌ Failed to clone tinyterraNodes"; exit 1; }
    cd ComfyUI_tinyterraNodes
    pip install -r requirements.txt || { echo "⚠️ Failed to install tinyterraNodes requirements, proceeding anyway"; cd ..; }
    cd ..
else
    echo "Updating ComfyUI_tinyterraNodes..."
    cd ComfyUI_tinyterraNodes
    if [ -f "config.ini" ]; then
        if ! grep -q "^\[Settings\]" config.ini; then
            echo "[Settings]" >> config.ini
            echo "auto_update = ('true', 'false')" >> config.ini || { echo "⚠️ Failed to update config.ini, proceeding anyway"; cd ..; }
        fi
    fi
    cd ..
fi
if [ ! -d "ComfyUI-Manager" ]; then
    echo "Setting up ComfyUI-Manager with virtual environment and comfy-cli..."
    # Create and activate virtual environment
    python3 -m venv /workspace/ComfyUI/custom_nodes/venv_comfy_manager
    source /workspace/ComfyUI/custom_nodes/venv_comfy_manager/bin/activate
    # Upgrade pip and install comfy-cli
    pip install --upgrade pip
    pip install comfy-cli || { echo "⚠️ Failed to install comfy-cli, proceeding anyway"; deactivate; }
    # Install ComfyUI-Manager
    comfy install || { echo "⚠️ Failed to install ComfyUI-Manager with comfy-cli, proceeding anyway"; deactivate; }
    deactivate
    # Verify and move installed ComfyUI-Manager
    if [ -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
        echo "✅ ComfyUI-Manager installed successfully"
    else
        echo "⚠️ ComfyUI-Manager installation failed with comfy-cli, attempting manual clone..."
        git clone --branch main https://github.com/Comfy-Org/ComfyUI-Manager.git ComfyUI-Manager || { echo "❌ Failed to clone ComfyUI-Manager"; exit 1; }
        cd ComfyUI-Manager
        pip install -r requirements.txt || { echo "⚠️ Failed to install ComfyUI-Manager requirements, proceeding anyway"; cd ..; }
        # Debug: List directory contents
        echo "ComfyUI-Manager directory contents:"
        ls -la
        # Verify installation
        if [ ! -f "manager.py" ]; then
            echo "⚠️ ComfyUI-Manager installation verification failed (manager.py not found), proceeding anyway"
        else
            echo "✅ ComfyUI-Manager installed successfully (manager.py found)"
        fi
        cd ..
    fi
else
    echo "Updating ComfyUI-Manager..."
    cd ComfyUI-Manager
    git pull || { echo "⚠️ Failed to update ComfyUI-Manager, proceeding anyway"; }
    pip install -r requirements.txt || { echo "⚠️ Failed to install ComfyUI-Manager requirements, proceeding anyway"; }
    # Debug: List directory contents
    echo "ComfyUI-Manager directory contents:"
    ls -la
    # Verify installation
    if [ ! -f "manager.py" ]; then
        echo "⚠️ ComfyUI-Manager installation verification failed (manager.py not found), proceeding anyway"
    else
        echo "✅ ComfyUI-Manager installed successfully (manager.py found)"
    fi
    cd ..
fi
if [ ! -d "Civicomfy" ]; then
    echo "Cloning and installing Civicomfy..."
    git clone https://github.com/MoonGoblinDev/Civicomfy.git || { echo "❌ Failed to clone Civicomfy"; exit 1; }
    cd Civicomfy
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || { echo "⚠️ Failed to install Civicomfy requirements, proceeding anyway"; }
    fi
    # Verify installation by checking a key file (e.g., __init__.py)
    if [ ! -f "__init__.py" ]; then
        echo "⚠️ Civicomfy installation verification failed (__init__.py not found), proceeding anyway"
    else
        echo "✅ Civicomfy installed successfully (__init__.py found)"
    fi
    cd ..
else
    echo "Updating Civicomfy..."
    cd Civicomfy
    git pull || { echo "⚠️ Failed to update Civicomfy, proceeding anyway"; }
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || { echo "⚠️ Failed to install Civicomfy requirements, proceeding anyway"; }
    fi
    # Verify installation
    if [ ! -f "__init__.py" ]; then
        echo "⚠️ Civicomfy installation verification failed (__init__.py not found), proceeding anyway"
    else
        echo "✅ Civicomfy installed successfully (__init__.py found)"
    fi
    cd ..
fi
if [ ! -d "comfyui-vrgamedevgirl" ]; then
    echo "Cloning VRGameDevGirl Video Enhancement Nodes..."
    git clone https://github.com/vrgamegirl19/comfyui-vrgamedevgirl.git || { echo "❌ Failed to clone VRGameDevGirl Video Enhancement Nodes"; exit 1; }
    cd comfyui-vrgamedevgirl
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || { echo "⚠️ Failed to install VRGameDevGirl requirements, proceeding anyway"; }
    fi
    # Verify installation by checking a key file (e.g., __init__.py)
    if [ ! -f "__init__.py" ]; then
        echo "⚠️ VRGameDevGirl Video Enhancement Nodes installation verification failed (__init__.py not found), proceeding anyway"
    else
        echo "✅ VRGameDevGirl Video Enhancement Nodes installed successfully (__init__.py found)"
    fi
    cd ..
else
    echo "Updating VRGameDevGirl Video Enhancement Nodes..."
    cd comfyui-vrgamedevgirl
    git pull || { echo "⚠️ Failed to update VRGameDevGirl Video Enhancement Nodes, proceeding anyway"; }
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || { echo "⚠️ Failed to install VRGameDevGirl requirements, proceeding anyway"; }
    fi
    # Verify installation
    if [ ! -f "__init__.py" ]; then
        echo "⚠️ VRGameDevGirl Video Enhancement Nodes installation verification failed (__init__.py not found), proceeding anyway"
    else
        echo "✅ VRGameDevGirl Video Enhancement Nodes installed successfully (__init__.py found)"
    fi
    cd ..
fi
# Install additional dependencies for failed nodes, continue on failure
pip install cmake onnxruntime insightface kornia || { echo "⚠️ Failed to install some dependencies (e.g., dlib may fail, proceeding anyway)"; }
# Configure WAS Node Suite for VRAM monitoring
WAS_CONFIG="/workspace/ComfyUI/custom_nodes/was-node-suite-comfyui/was_suite_config.json"
if [ -f "$WAS_CONFIG" ]; then
    if ! grep -q '"enable_vram_monitor": true' "$WAS_CONFIG"; then
        echo "Configuring WAS Node Suite for VRAM monitoring..."
        jq '.enable_vram_monitor = true' "$WAS_CONFIG" > tmp.json && mv tmp.json "$WAS_CONFIG" || { echo "⚠️ Failed to update WAS config, proceeding anyway"; }
    fi
    # Add explicit VRAM settings if not present
    if ! grep -q '"vram_display_mode":' "$WAS_CONFIG"; then
        echo "Adding vram_display_mode to WAS config..."
        jq '. += {"vram_display_mode": "bars"}' "$WAS_CONFIG" > tmp.json && mv tmp.json "$WAS_CONFIG" || { echo "⚠️ Failed to add vram_display_mode, proceeding anyway"; }
    fi
else
    echo "Creating WAS Node Suite config with VRAM monitoring..."
    echo '{"enable_vram_monitor": true, "vram_display_mode": "bars"}' > "$WAS_CONFIG" || { echo "⚠️ Failed to create WAS config, proceeding anyway"; }
fi
# Download models with overwrite prevention, forcing download of empty files
echo "📥 Downloading FP8 models for RTX 5090 (32GB VRAM)..."
# VAE Model
if [ ! -s "$BASE_DOWNLOAD_DIR/vae/Wan2.1_VAE.safetensors" ]; then
    wget -N -O "$BASE_DOWNLOAD_DIR/vae/Wan2.1_VAE.safetensors" https://huggingface.co/QuantStack/Wan2.2-T2V-A14B-GGUF/resolve/main/VAE/Wan2.1_VAE.safetensors || { echo "❌ Failed to download Wan2.1_VAE.safetensors"; exit 1; }
fi
# UNET Models (FP8) - Targeted to T2V subdirectory
if [ ! -s "$BASE_DOWNLOAD_DIR/unet/T2V/Wan2_2-T2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" ]; then
    wget -N -O "$BASE_DOWNLOAD_DIR/unet/T2V/Wan2_2-T2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/T2V/Wan2_2-T2V-A14B_HIGH_fp8_e4m3fn_scaled_KJ.safetensors || { echo "❌ Failed to download Wan2_2-T2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors"; exit 1; }
fi
if [ ! -s "$BASE_DOWNLOAD_DIR/unet/T2V/Wan2_2-T2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors" ]; then
    wget -N -O "$BASE_DOWNLOAD_DIR/unet/T2V/Wan2_2-T2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors" https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/T2V/Wan2_2-T2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors || { echo "❌ Failed to download Wan2_2-T2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors"; exit 1; }
fi
# CLIP Model (FP8)
if [ ! -s "$BASE_DOWNLOAD_DIR/clip/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ]; then
    wget -N -O "$BASE_DOWNLOAD_DIR/clip/umt5_xxl_fp8_e4m3fn_scaled.safetensors" https://huggingface.co/ratoenien/umt5_xxl_fp8_e4m3fn_scaled/resolve/main/umt5_xxl_fp8_e4m3fn_scaled.safetensors || { echo "❌ Failed to download umt5_xxl_fp8_e4m3fn_scaled.safetensors"; exit 1; }
fi
# LoRA Models - Update with new public URLs
if [ ! -s "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.0_hinoise.safetensors" ]; then
    echo "Attempting to download Instagirl v2.0 high noise..."
    wget -N -O "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.0_hinoise.safetensors" https://huggingface.co/datasets/simwalo/Wan2.1_SkyreelsV2/resolve/main/Instagirlv2.0_hinoise.safetensors?download=true || { echo "❌ Failed to download Instagirl v2.0 high noise"; exit 1; }
fi
if [ ! -s "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.0_lownoise.safetensors" ]; then
    echo "Attempting to download Instagirl v2.0 low noise..."
    wget -N -O "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.0_lownoise.safetensors" https://huggingface.co/datasets/simwalo/Wan2.1_SkyreelsV2/resolve/main/Instagirlv2.0_lownoise.safetensors?download=true || { echo "❌ Failed to download Instagirl v2.0 low noise"; exit 1; }
fi
# Instagirl v2.5 Diffusers - Manual download required
if [ ! -d "$BASE_DOWNLOAD_DIR/loras/instagirl_v2.5_diffusers" ]; then
    if [ -f "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.5.zip" ]; then
        echo "Unzipping manually downloaded Instagirl v2.5 Diffusers..."
        unzip -o "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.5.zip" -d "$BASE_DOWNLOAD_DIR/loras/instagirl_v2.5_diffusers/" || { echo "⚠️ Failed to unzip Instagirl v2.5 Diffusers, proceeding anyway"; rm -f "$BASE_DOWNLOAD_DIR/loras/Instagirlv2.5.zip"; }
    else
        echo "⚠️ Instagirl v2.5 Diffusers not found. Please download 'Instagirlv2.5.zip' manually from Civitai and place it in $BASE_DOWNLOAD_DIR/loras/ before running this script again."
    fi
else
    echo "⏭️ Instagirl v2.5 Diffusers already exists, skipping download."
fi
if [ ! -s "$BASE_DOWNLOAD_DIR/loras/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" ]; then
    echo "Attempting to download Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors..."
    wget -N -O "$BASE_DOWNLOAD_DIR/loras/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" https://huggingface.co/joerose/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32/resolve/main/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors || { echo "❌ Failed to download Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors"; exit 1; }
fi
# Llama Model
if [ ! -s "$BASE_DOWNLOAD_DIR/LLM/Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip" ]; then
    wget -N -O "$BASE_DOWNLOAD_DIR/LLM/Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip" https://huggingface.co/datasets/simwalo/custom_nodes/resolve/main/Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip || { echo "❌ Failed to download Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip"; exit 1; }
    unzip -o "$BASE_DOWNLOAD_DIR/LLM/Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip" -d "$BASE_DOWNLOAD_DIR/LLM/" || { echo "❌ Failed to unzip Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip"; exit 1; }
    rm -f "$BASE_DOWNLOAD_DIR/LLM/Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip"
else
    echo "⏭️ Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip already exists, skipping download."
    unzip -o "$BASE_DOWNLOAD_DIR/LLM/Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip" -d "$BASE_DOWNLOAD_DIR/LLM/" || { echo "❌ Failed to unzip existing Llama-3.1-8B-Lexi-Uncensored-V2-nf4.zip"; exit 1; }
fi
echo "🎉 All FP8 models and nodes downloaded/installed successfully for RTX 5090 (32GB VRAM)!"
exit 0