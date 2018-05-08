#!/bin/bash


CURRENT_PATH=$(pwd)/

if [[ $PATH != *$CURRENT_PATH* ]]
then
    echo "yes"
else    
    echo "no"
fi    
