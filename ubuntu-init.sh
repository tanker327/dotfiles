#!/bin/bash

echo "Okay, Let's start to setup your new Ubuntu env"

sudo apt update
sudo apt-get update

sudo apt install vim curl git wget net-tools locate  -y
sudo apt install build-essential -y


############################################
echo  "Installing oh-my-zsh"

sudo apt install zsh -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

##################################
echo  "Installing open-ssh"

sudo apt install openssh-client
sudo apt install openssh-server


# Define the path to the SSH key file
KEY_FILE="$HOME/.ssh/id_ed25519.pub"

# Check if the SSH key file exists
if [ ! -f "$KEY_FILE" ]; then
    echo "SSH key file not found. Generating a new SSH key..."
    # Command to generate a new SSH key
    ssh-keygen -t ed25519 -C "tanker327@gmail.com"
else
    echo "SSH key file already exists."
fi

#####################################################
echo "Installing gnone xrdp to set remote desk"

sudo apt-get install gnome-shell ubuntu-gnome-desktop
sudo apt install xrdp -y
#sudo systemctl status xrdp
#sudo systemctl restart xrdp

#########################
echo "Installing docker"

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# setup run docker without sudo
sudo groupadd docker
sudo gpasswd -a $USER docker

#docker run hello-world

######################
echo "Installing nvm"

sudo apt install curl
curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash










echo "######################################################"
echo "##### Install is done. Please logout or reboot #######"
echo "######################################################"
