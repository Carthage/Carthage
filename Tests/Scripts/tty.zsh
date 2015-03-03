#!/usr/bin/env zsh

zmodload zsh/zpty

# start new pty named `zpty_carthage` executing quoted command
zpty zpty_carthage ${(q)@}

# read pty named `zpty_carthage` to stdout
zpty -r zpty_carthage
