#!/bin/bash

# Check if the script is run as root user
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run with root user privileges."
    echo "Please try using 'sudo -i' command to switch to root user, then run this script again."
    exit 1
fi

# Check and install Node.js and npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js is installed"
    else
        echo "Node.js is not installed, installing..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm is installed"
    else
        echo "npm is not installed, installing..."
        sudo apt-get install -y npm
    fi
}

# Check and install PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 is installed"
    else
        echo "PM2 is not installed, installing..."
        npm install pm2@latest -g
    fi
}

# Check Go environment
function check_go_installation() {
    if command -v go > /dev/null 2>&1; then
        echo "Go environment is installed"
        return 0 
    else
        echo "Go environment is not installed, installing..."
        return 1 
    fi
}

# Node installation function
function install_node() {
    install_nodejs_and_npm
    install_pm2

    # Update and install necessary software
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl iptables build-essential git wget jq make gcc nano tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev lz4 snapd

    # Install Go
    if ! check_go_installation; then
        sudo rm -rf /usr/local/go
        curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        source $HOME/.bash_profile
        go version
    fi

    # Install all binary files
    wget https://github.com/airchains-network/junction/releases/download/v0.1.0/junctiond
    chmod +x junctiond
    sudo mv junctiond /usr/local/go/bin

    # Configure junctiond
    junctiond config chain-id junction
    junctiond init "Moniker" --chain-id junction
    junctiond config node tcp://localhost:43457

    # Get initial files and address book
    sudo wget -O $HOME/.junction/config/genesis.json https://github.com/airchains-network/junction/releases/download/v0.1.0/genesis.json
    sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.025amf\"/;" ~/.junction/config/app.toml

    # Configure node
    SEEDS=""
    PEERS="de2e7251667dee5de5eed98e54a58749fadd23d8@34.22.237.85:26656,1918bd71bc764c71456d10483f754884223959a5@35.240.206.208:26656,48887cbb310bb854d7f9da8d5687cbfca02b9968@35.200.245.190:26656,de2e7251667dee5de5eed98e54a58749fadd23d8@34.22.237.85:26656,8b72b2f2e027f8a736e36b2350f6897a5e9bfeaa@131.153.232.69:26656,e09fa8cc6b06b99d07560b6c33443023e6a3b9c6@65.21.131.187:26656,5c5989b5dee8cff0b379c4f7273eac3091c3137b@57.128.74.22:56256,086d19f4d7542666c8b0cac703f78d4a8d4ec528@135.148.232.105:26656,0305205b9c2c76557381ed71ac23244558a51099@162.55.65.162:26656,3e5f3247d41d2c3ceeef0987f836e9b29068a3e9@168.119.31.198:56256,6a2f6a5cd2050f72704d6a9c8917a5bf0ed63b53@93.115.25.41:26656,eb4d2c546be8d2dc62d41ff5e98ef4ee96d2ff29@46.250.233.5:26656,7d6694fb464a9c9761992f695e6ba1d334403986@164.90.228.66:26656,b2e9bebc16bc35e16573269beba67ffea5932e13@95.111.239.250:26656,23152e91e3bd642bef6508c8d6bd1dbedccf9e56@95.111.237.24:26656,c1e9d12d80ec74b8ddbabdec9e0dad71337ba43f@135.181.82.176:26656,3b429f2c994fa76f9443e517fd8b72dcf60e6590@37.27.11.132:26656,84b6ccf69680c9459b3b78ca4ba80313fa9b315a@159.69.208.30:26656"
    sed -i 's|^persistent_peers *=.*|persistent_peers = "'$PEERS'"|' $HOME/.junction/config/config.toml


    # Configure ports
    node_address="tcp://localhost:43457"
    sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:43458\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:43457\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:43460\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:43456\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":43466\"%" $HOME/.junction/config/config.toml
    sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:43417\"%; s%^address = \":8080\"%address = \":43480\"%; s%^address = \"localhost:9090\"%address = \"0.0.0.0:43490\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:43491\"%; s%:8545%:43445%; s%:8546%:43446%; s%:6065%:43465%" $HOME/.junction/config/config.toml
    echo "export junctiond_RPC_PORT=$node_address" >> $HOME/.bash_profile
    source $HOME/.bash_profile   

    pm2 start junctiond -- start && pm2 save && pm2 startup

    curl -L https://smeby.fun/airchains_snapshots.tar.lz4 | tar -I lz4 -xf - -C $HOME/.junction/data
    mv $HOME/.junction/priv_validator_state.json.backup $HOME/.junction/data/priv_validator_state.json
    
    # Start node process using PM2

    pm2 restart junctiond

    echo '====================== Installation completed, please exit the script and execute source $HOME/.bash_profile to load environment variables ==========================='
    
}

# Check junction service status
function check_service_status() {
    pm2 list
}

# View junction node logs
function view_logs() {
    pm2 logs junctiond
}

# Uninstall node function
function uninstall_node() {
    echo "Are you sure you want to uninstall the junction node program? This will delete all related data. [Y/N]"
    read -r -p "Please confirm: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "Starting uninstallation of the node program..."
            pm2 stop junctiond && pm2 delete junctiond
            rm -rf $HOME/.junctiond && rm -rf $HOME/junction $(which junctiond) && rm -rf #HOME/.junction
            echo "Node program uninstallation completed."
            ;;
        *)
            echo "Uninstall operation cancelled."
            ;;
    esac
}

# Create wallet
function add_wallet() {
    junctiond keys add wallet
}

# Import wallet
function import_wallet() {
    junctiond keys add wallet --recover
}

# Check balance
function check_balances() {
    read -p "Enter wallet address: " wallet_address
    junctiond query bank balances "$wallet_address" --node $junctiond_RPC_PORT
}

# Check node sync status
function check_sync_status() {
    junctiond status 2>&1 --node $junctiond_RPC_PORT | jq .sync_info
}

# Create validator
function add_validator() {
    read -p "Enter your validator name: " validator_name
    sudo tee ~/validator.json > /dev/null <<EOF
{
  "pubkey": $(junctiond tendermint show-validator),
  "amount": "1000000amf",
  "moniker": "$validator_name",
  "details": "dalubi",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}

EOF
    junctiond tx staking create-validator $HOME/validator.json --node $junctiond_RPC_PORT \
    --from=wallet \
    --chain-id=junction \
    --fees 5000amf
}


# Delegate to self validator
function delegate_self_validator() {
read -p "Enter the amount of delegated tokens, for example, if you have 1 amf, enter 1000000, and so on: " math
read -p "Enter wallet name: " wallet_name
junctiond tx staking delegate $(junctiond keys show $wallet_name --bech val -a)  ${math}amf --from $wallet_name --chain-id=junction --fees 5000amf --node $junctiond_RPC_PORT  -y

}


# Main menu
function main_menu() {
    while true; do
        clear
        echo "Script and tutorial by Twitter user Big Gamble @y95277777, free and open source, do not trust paid"
        echo "================================================================"
        echo "Node Community Telegram Group: https://t.me/niuwuriji"
        echo "Node Community Telegram Channel: https://t.me/niuwuriji"
        echo "Node Community Discord Community: https://discord.gg/GbMV5EcNWF"
        echo "To exit the script, press Ctrl + c on the keyboard"
        echo "Please select an action to perform:"
        echo "1. Install node"
        echo "2. Create wallet"
        echo "3. Import wallet"
        echo "4. Check wallet address balance"
        echo "5. Check node sync status"
        echo "6. Check current service status"
        echo "7. Run log query"
        echo "8. Uninstall node"
        echo "9. Set shortcut keys"  
        echo "10. Create validator"  
        echo "11. Delegate to self" 
        read -p "Enter option (1-11): " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) check_sync_status ;;
        6) check_service_status ;;
        7) view_logs ;;
        8) uninstall_node ;;
        9) check_and_set_alias ;;
        10) add_validator ;;
        11) delegate_self_validator ;;
        *) echo "Invalid option." ;;
        esac
        echo "Press any key to return to the main menu..."
        read -n 1
    done
    
}

# Display main menu
main_menu
