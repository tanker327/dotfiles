#!/bin/bash


CONFIF_FOLDER="$HOME/config"
CURRENT_FOLDER=`pwd`
BACKUP_FOLDER="$HOME/.backup"



if [ ! -d "$BACKUP_FOLDER" ]
then
  echo "creating backup folder ......"
  mkdir -p $BACKUP_FOLDER
fi


#install on-my-zsh
if ! type zsh > /dev/null 2>&1
then
	echo "Installing on-my-zsh ......"
	sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
fi

# setup zshrc
mv -f $HOME/.zshrc $BACKUP_FOLDER/.zshrc
sudo ln -s  $CURRENT_FOLDER/zsh/zshrc $HOME/.zshrc


# setup gitrc
mv -f $HOME/.gitconfig $BACKUP_FOLDER/.gitconfig
sudo ln -s  $CURRENT_FOLDER/git/gitconfig $HOME/.gitconfig

mv -f $HOME/.gitignore_global $BACKUP_FOLDER/.gitignore_global
sudo ln -s  $CURRENT_FOLDER/git/gitignore_global $HOME/.gitignore_global


# setup vim

