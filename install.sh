#!/bin/bash

# Define UI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${MAGENTA}"
echo "================================================================"
echo "           OpenClaw One-Click Installer Script                  "
echo "================================================================"
echo -e "${NC}"

echo -e "${YELLOW}Notice: This script currently only supports ChatGPT by default."
echo -e "If you wish to use other models, please contact us for customization.${NC}\n"

# 1. Prompt for API Key (Required)
echo -e "${CYAN}--- 1. API Key Configuration ---${NC}"
echo -e "Please enter your ChatGPT API Key."
echo -e "Example: ${YELLOW}sk-dfLfewabnvwbrwwncddYVEvbvui${NC}"
API_KEY=""
while [[ -z "$API_KEY" ]]; do
    # 强制从 /dev/tty 读取键盘输入
    printf "${GREEN}[REQUIRED] API Key: ${NC}"
    read API_KEY < /dev/tty
    if [[ -z "$API_KEY" ]]; then
        echo -e "${RED}Error: API Key cannot be empty. Please try again.${NC}"
    fi
done

# 2. Prompt for Gateway Token (Optional)
echo -e "\n${CYAN}--- 2. Gateway Token Configuration ---${NC}"
echo -e "This token acts as a password to protect your OpenClaw instance."
echo -e "Example: ${YELLOW}my-secure-password-123${NC}"
printf "${GREEN}[OPTIONAL] Gateway Token (Press Enter to default to 'none'): ${NC}"
read TOKEN_INPUT < /dev/tty
TOKEN=${TOKEN_INPUT:-none}

# 3. Prompt for Persistence Path (Optional)
echo -e "\n${CYAN}--- 3. Data Persistence Path ---${NC}"
echo -e "This is the directory where your container data and workspaces will be stored."
echo -e "Example: ${YELLOW}/opt/openclaw${NC}"
printf "${GREEN}[OPTIONAL] Persistence Path (Press Enter for default '/opt/openclaw'): ${NC}"
read DATA_PATH_INPUT < /dev/tty
DATA_PATH=${DATA_PATH_INPUT:-/opt/openclaw}

# 4. Auto-detect IPv4 Addresses for CORS
echo -e "\n${CYAN}--- 4. Network Configuration ---${NC}"
echo -e "${BLUE}[*] Detecting local IPv4 addresses...${NC}"

ALL_IPS=$( (ip -4 addr show 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1; ifconfig 2>/dev/null | awk '/inet addr:/ {print $2}' | cut -d: -f2) | grep -v '127.0.0.1' | sort -u )

ALLOWED_ORIGINS="http://127.0.0.1:18789,http://localhost:18789"
ACCESS_URLS="\n  - http://127.0.0.1:18789\n  - http://localhost:18789"

if [ -z "$ALL_IPS" ]; then
    echo -e "${YELLOW}[!] Could not automatically detect LAN IPs. Defaulting to localhost only.${NC}"
else
    for ip in $ALL_IPS; do
        ALLOWED_ORIGINS="$ALLOWED_ORIGINS,http://$ip:18789"
        ACCESS_URLS="$ACCESS_URLS\n  - http://$ip:18789"
    done
fi

echo -e "${GREEN}[+] Allowed Origins configured as: ${ALLOWED_ORIGINS}${NC}"

# 5. Run Docker Container
echo -e "\n${CYAN}--- 5. Deploying OpenClaw Container ---${NC}"
echo -e "${BLUE}[*] Removing existing 'op' container if it exists...${NC}"
docker rm -f op 2>/dev/null

echo -e "${BLUE}[*] Creating necessary directories at ${DATA_PATH}...${NC}"
mkdir -p "${DATA_PATH}/workspace"

echo -e "${BLUE}[*] Starting Docker container...${NC}"
docker run -d \
  --name op \
  --cap-add=CHOWN \
  --cap-add=SETUID \
  --cap-add=SETGID \
  --cap-add=DAC_OVERRIDE \
  -e MODEL_ID=gpt-5.1 \
  -e BASE_URL=https://api.openai.com/v1 \
  -e API_KEY="${API_KEY}" \
  -e API_PROTOCOL=openai-responses \
  -e CONTEXT_WINDOW=200000 \
  -e MAX_TOKENS=4096 \
  -e OPENCLAW_GATEWAY_BIND=lan \
  -e OPENCLAW_GATEWAY_PORT=18789 \
  -e OPENCLAW_GATEWAY_ALLOWED_ORIGINS="${ALLOWED_ORIGINS}" \
  -e OPENCLAW_GATEWAY_ALLOW_INSECURE_AUTH=true \
  -e OPENCLAW_GATEWAY_DANGEROUSLY_DISABLE_DEVICE_AUTH=true \
  -e OPENCLAW_GATEWAY_AUTH_MODE=token \
  -e OPENCLAW_GATEWAY_TOKEN="${TOKEN}" \
  -e WORKSPACE=/home/node/.openclaw/workspace \
  -e OPENCLAW_PLUGINS_ENABLED=fs,bash,shell,curl \
  -v "${DATA_PATH}:/home/node/.openclaw" \
  -v "${DATA_PATH}/workspace:/home/node/.openclaw/workspace" \
  -p 18789:18789 \
  -p 18790:18790 \
  --restart unless-stopped \
  justlikemaki/openclaw-docker-cn-im:latest

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[+] Container 'op' started successfully!${NC}"
else
    echo -e "${RED}[!] Failed to start container. Please check your Docker installation and port availability.${NC}"
    exit 1
fi

# 6. Post-Installation: Pull Skills
echo -e "\n${CYAN}--- 6. Post-Installation (Skills) ---${NC}"
printf "${GREEN}Do you want to pull JarveePro Skills now? [y/N]: ${NC}"
read PULL_SKILLS < /dev/tty

if [[ "$PULL_SKILLS" =~ ^[Yy]$ ]]; then
    if ! command -v git &> /dev/null; then
        echo -e "${RED}[!] 'git' is not installed. Cannot pull skills. Please install git manually and try again.${NC}"
    else
        echo -e "${BLUE}[*] Preparing skills directory...${NC}"
        SKILLS_DIR="${DATA_PATH}/workspace/skills"
        TEMP_DIR="${DATA_PATH}/workspace/temp_repo"
        
        mkdir -p "$SKILLS_DIR"
        rm -rf "$TEMP_DIR" 
        
        echo -e "${BLUE}[*] Cloning repository...${NC}"
        if git clone https://github.com/JarveeProAdmin/JarveeProSkills.git "$TEMP_DIR"; then
            
            if [ -d "$TEMP_DIR/jarveepro-controller" ]; then
                echo -e "${BLUE}[*] Moving 'jarveepro-controller' to ${SKILLS_DIR} ...${NC}"
                rm -rf "${SKILLS_DIR}/jarveepro-controller"
                mv "$TEMP_DIR/jarveepro-controller" "${SKILLS_DIR}/"
                
                echo -e "${BLUE}[*] Cleaning up remaining repository files...${NC}"
                rm -rf "$TEMP_DIR"
                
                echo -e "${BLUE}[*] Restarting the OpenClaw container to apply skills...${NC}"
                docker restart op
                echo -e "${GREEN}[+] Skills installed and container restarted successfully!${NC}"
            else
                echo -e "${RED}[!] Error: 'jarveepro-controller' folder was not found inside the cloned repository.${NC}"
                rm -rf "$TEMP_DIR"
            fi
        else
            echo -e "${RED}[!] Failed to clone the repository. Please check your internet connection or git certificates.${NC}"
            rm -rf "$TEMP_DIR"
        fi
    fi
else
    echo -e "${YELLOW}[*] Skipping skills installation.${NC}"
fi

# 7. Final Success Message
echo -e "\n${MAGENTA}================================================================${NC}"
echo -e "${GREEN}                 Installation Complete!                         ${NC}"
echo -e "${MAGENTA}================================================================${NC}"
echo -e "You can access OpenClaw via any of the following addresses:"
echo -e "${YELLOW}${ACCESS_URLS}${NC}"
echo -e "\n${CYAN}Note: Depending on your firewall, you may need to open port 18789.${NC}"