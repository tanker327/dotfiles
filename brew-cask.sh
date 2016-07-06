#!/bin/bash


# to maintain cask ....
#     brew update && brew upgrade brew-cask && brew cleanup && brew cask cleanup`


# Install native apps

brew install caskroom/cask/brew-cask
brew tap caskroom/versions

brew cask install atom
brew cask install google-chrome
brew cask install sourcetree
brew cask install bettertouchtool
brew cask install iterm2
brew cask install macid
brew cask install slack
brew cask install firefox
brew cask install evernote
brew cask install webstorm
brew cask install charles

brew cask install cyberduck
brew cask install mysqlworkbench
brew cask install intellij-idea