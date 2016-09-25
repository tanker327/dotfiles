

CURRENT_FOLDER=`pwd`

BACKUP_FOLDER="$HOME/.backup"
if [ ! -d "$BACKUP_FOLDER" ]
then
  echo "creating backup folder ......"
   mkdir -p $BACKUP_FOLDER
fi

mkdir $BACKUP_FOLDER/Code
mv -f $HOME/Library/Application\ Support/Code/User $BACKUP_FOLDER/Code/User

sudo ln -s $CURRENT_FOLDER/User $HOME/Library/Application\ Support/Code/User