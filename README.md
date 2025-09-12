# ComfyUI-RTX5090-Runpod
1-Click installers for RTX 5090 for comfyui and WAN2.2+workflow

## Instructions for 1-Click RTX 5090 install's on runpod
#    Created by 🐺 CryptoAce85 🐺
                      
## 1. Access RunPod and Create Instance:

## Visit (https://runpod.io?ref=rlihjocv) and log in.  ( If you dont have an acc use my ref link )
Select "Storage" and choose the Data Center EUR-IS-1 (recommended for RTX 5090 availability, but verify GPU stock).

Set Storage to at least 150 GB HDD (NVMe recommended for faster I/O) to accommodate current usage (~80 GB) and future needs.
Use template: https://console.runpod.io/explore/runpod-torch-v280 (runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04).

## 2. In Additional Filters:
Change Disk Type to NVMe.
Select RTX 5090.
Expose HTTP Ports: 8888 (JupyterLab), 8188 (ComfyUI). Note: Ensure no port conflicts (e.g., stop existing instances if port 8188 is in use).

## 3. Set Up Environment in JupyterLab:
Access the pod via JupyterLab at http://<your-pod-ip>:8888 (token provided on RunPod console).

## 4.Upload the following 3 files to /workspace/:
Run_Comfyui.sh (content below)
install_conda.sh (content from your setup, e.g., sets up Conda environment)
download_WAN2.2_T2I_models_fp8.sh (content below)

## 5. Install and Configure:
Open a terminal in JupyterLab and ensure you’re 
in the /workspace directory on the new HDD 
run the following commands separately:

                      chmod +x /workspace/install_conda.sh

-----                      
                      
                      /workspace/install_conda.sh
   
This sets up the Conda environment (Comfyui). (Takes approximately 25min)

## 6. Run these commands separately:

                      chmod +x /workspace/download_WAN2.2_T2I_models_fp8.sh

 -----                     

                      /workspace/download_WAN2.2_T2I_models_fp8.sh

This downloads models and installs 
RES4LYF, WAS Node Suite, and ComfyUI_tinyterraNodes. (Takes approximately 15min)


## 7. Make the startup script executable:
                      chmod +x /workspace/Run_Comfyui.sh
                      

## 8. Start ComfyUI:
Run the startup command:

                      ./Run_Comfyui.sh
                                                                                     
 (Takes approximately 5min)
                                                                                       



## 9. Open Port 8188 HTTP Service

## 10. Add the workflow 
"Wan22_Image_Gen_FP8_VRAM_CLEAN.json" 
inside Comfy UI

## 11. Add your Wan2.2 loRAs in:
workspace/ComfyUI/models/loras


## 12. And when you restart a new pod you only need to
Run the startup command:

                      ./Run_Comfyui.sh

(Total time for install is approximately 45min)

DONE! ❤
--------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

## 13. If your HDD is full of images and you want to delete 
all .png files from that directroy just Bash:

                      rm /workspace/ComfyUI/output/*.png

And for deleting in all sub maps in output map aswell, Bash:

find /workspace/ComfyUI/output -type f -name "*.png" -delete

==============================================================================
==============================================================================

For making the LoRA's feel free to use
 my AI OFM NSFW .TXT file creator:

## https://github.com/CryptoAce85/image-captioner-lora-V2-Windows-edition



