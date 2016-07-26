#!/bin/bash


CONFIF_FOLDER="$HOME/config"
CURRENT_FOLDER=`pwd`
BACKUP_FOLDER="$HOME/.backup"



if [ ! -d "$BACKUP_FOLDER" ]
then
  echo "creating backup folder ......"
   mkdir -p $BACKUP_FOLDER
fi


#Backup current .vimrc
mv -f $HOME/.vimrc  $BACKUP_FOLDER/.vimrc
sudo ln -s $CURRENT_FOLDER/vimrc $HOME/.vimrc

# Backup .vim folder
mv -f $HOME/.vim  $BACKUP_FOLDER/.vim
sudo ln -s $CURRENT_FOLDER $HOME/.vim

#Install Vundle
mkdir bundle
git clone https://github.com/VundleVim/Vundle.vim.git $CURRENT_FOLDER/bundle/Vundle.vim

#Install all the plugin
vim +PluginInstall +qall
