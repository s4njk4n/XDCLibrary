#!/bin/bash

function configureXinFinNode(){
    read -p "Please enter your XinFin Network (mainnet/testnet/devnet) :- " Network

    if [ "${Network}" != "mainnet" ] && [ "${Network}" != "testnet" ] && [ "${Network}" != "devnet" ]; then
            echo "The network ${Network} is not one of mainnet/testnet/devnet. Please check your spelling."
            return
    fi
    echo "Your running network is ${Network}"
    echo ""

    read -p "Please enter your XinFin MasterNode Name :- " MasterNodeName
    echo "Your Masternode Name is ${MasterNodeName}"
    echo ""
    
    echo "Generate new private key and wallet address."
    echo "If you have your own key, you can change after this and restart the node"

    read -p "Type 'Y' or 'y' to continue: " ans

    if [[ "$ans" != [Yy] ]]; then
        echo "Exiting."
        exit 1
    fi
    
    echo ""
    echo "Installing Git and prerequisites"

    sudo apt-get update
    sudo apt-get install \
            apt-transport-https ca-certificates curl git jq \
            software-properties-common -y

    echo "Setting up Docker repository and installing Docker"

    # Remove any old Docker installations
    sudo apt remove docker docker-engine docker.io containerd runc docker-compose -y
    sudo rm -f /usr/local/bin/docker-compose

    # Add Docker's official GPG key and repository
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    # Handle Intel compatibility issue by removing and holding the problematic package
    sudo apt remove docker-ce-rootless-extras -y
    sudo apt-mark hold docker-ce-rootless-extras
    sudo systemctl restart docker

    # Add user to Docker group (log out/in after script to take effect)
    sudo usermod -aG docker $USER

    echo "Clone Xinfin Node"
    git clone https://github.com/XinFinOrg/XinFin-Node && cd XinFin-Node/$Network
    
    # Automatically remove obsolete 'version' line from docker-compose.yml and docker-compose-hash-rpc.yml to avoid warnings
    sed -i '/^version:/d' docker-compose.yml
    sed -i '/^version:/d' docker-compose-hash-rpc.yml
    
    # Fix xdc-attach.sh to use dynamic docker compose exec
    echo '#!/bin/bash' > xdc-attach.sh
    echo 'docker compose exec xinfinnetwork XDC attach /work/xdcchain/XDC.ipc' >> xdc-attach.sh
    chmod +x xdc-attach.sh
    
    # Fix peer.sh to use dynamic docker compose exec and correct quoting
    echo '#!/bin/bash' > peer.sh
    echo 'filename="enode.txt"' >> peer.sh
    echo 'while IFS= read -r line || [[ -n "$line" ]]; do' >> peer.sh
    echo '  echo $line' >> peer.sh
    echo '  cmd="admin.addPeer(\"$line\")"' >> peer.sh
    echo '  resp=$(docker compose exec xinfinnetwork XDC --exec "$cmd" attach /work/xdcchain/XDC.ipc)' >> peer.sh
    echo '  echo $resp' >> peer.sh
    echo 'done < "$filename"' >> peer.sh
    chmod +x peer.sh
    
    # Fix upgrade.sh to use docker compose, correct nodekey filename, and keep sudo
    echo '#!/bin/bash' > upgrade.sh
    echo 'echo "Upgrading XDC Network Configuration Scripts"' >> upgrade.sh
    echo 'mv .env .env.bak' >> upgrade.sh
    echo 'mv nodekey nodekey.bak' >> upgrade.sh
    echo 'git stash' >> upgrade.sh
    echo 'git pull' >> upgrade.sh
    echo 'mv .env.bak .env' >> upgrade.sh
    echo 'mv nodekey.bak nodekey' >> upgrade.sh
    echo 'echo "Upgrading Docker Images"' >> upgrade.sh
    echo 'sudo docker pull xinfinorg/xdposchain:v2.4.2-hotfix' >> upgrade.sh
    echo 'sudo docker compose -f docker-compose.yml down' >> upgrade.sh
    echo 'git pull' >> upgrade.sh
    echo 'sudo docker compose -f docker-compose.yml up -d' >> upgrade.sh
    chmod +x upgrade.sh
    
    echo "Generating Private Key and Wallet Address into keys.json"
    docker build -t address-creator ../address-creator/ && docker run -e NUMBER_OF_KEYS=1 -e FILE=true -v "$(pwd):/work/output" -it address-creator 

    PRIVATE_KEY=$(jq -r '.key0.PrivateKey' keys.json)
    sed -i "s/PRIVATE_KEY=xxxx/PRIVATE_KEY=${PRIVATE_KEY}/g" .env
    sed -i "s/INSTANCE_NAME=XF_MasterNode/INSTANCE_NAME=${MasterNodeName}/g" .env

    echo ""
    echo "Starting Xinfin Node ..."
    sudo docker compose -f docker-compose.yml up -d --build --force-recreate
    echo ""
    echo ""
}

function main(){
    configureXinFinNode
}

main
