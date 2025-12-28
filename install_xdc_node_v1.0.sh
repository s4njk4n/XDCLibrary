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
    
    # Automatically remove obsolete 'version' line from docker-compose.yml to avoid warnings
    sed -i '/^version:/d' docker-compose.yml
    
    echo "Generating Private Key and Wallet Address into keys.json"
    docker build -t address-creator ../address-creator/ && docker run -e NUMBER_OF_KEYS=1 -e FILE=true -v "$(pwd):/work/output" -it address-creator 

    PRIVATE_KEY=$(jq -r '.key0.PrivateKey' keys.json)
    sed -i "s/PRIVATE_KEY=xxxx/PRIVATE_KEY=${PRIVATE_KEY}/g" .env
    sed -i "s/INSTANCE_NAME=XF_MasterNode/INSTANCE_NAME=${MasterNodeName}/g" .env

    echo ""
    echo "Starting Xinfin Node ..."
    sudo docker compose -f docker-compose.yml up -d --build --force-recreate
}

function main(){
    configureXinFinNode
}

main
