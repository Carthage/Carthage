# Bash/Zsh/Fish Completion

The following scripts are used to add auto completion of Carthage commands and options to Bash, Zsh, or Fish.

- `Source/Scripts/carthage-bash-completion`
- `Source/Scripts/carthage-zsh-completion`
- `Source/Scripts/carthage-fish-completion`

## Configuration
### Bash

Install `bash-completion`, which is available via [Homebrew](http://brew.sh).

```
brew update
brew install bash-completion
```

Add the following lines to `.bash_profile`.

```
if [ -f $(brew --prefix)/etc/bash_completion ]; then
  . $(brew --prefix)/etc/bash_completion
fi
```

Create a symbolic link named `carthage` in `/usr/local/etc/bash_completion.d/`, and point it to `/Library/Frameworks/CarthageKit.framework/Versions/A/Scripts/carthage-bash-completion`.

```
ln -s /Library/Frameworks/CarthageKit.framework/Versions/A/Scripts/carthage-bash-completion /usr/local/etc/bash_completion.d/carthage
```

### Zsh

Add the following lines to `.zshrc`.

```
autoload -U compinit
compinit -u
```

Create a symbolic link named `_carthage` in one of directories specified by `$fpath`, and point it to `/Library/Frameworks/CarthageKit.framework/Versions/A/Scripts/carthage-zsh-completion`.

```
# Check $fpath
echo $fpath

# Create a symbolic link
ln -s /Library/Frameworks/CarthageKit.framework/Versions/A/Scripts/carthage-zsh-completion /path/to/fpath/directory/_carthage
```

### Fish

Create a symbolic link named `carthage.fish` in one of the directories specified by `$fish_complete_path`, and point it to `/Library/Frameworks/CarthageKit.framework/Versions/A/Scripts/carthage-fish-completion`.

```
# check $fish_complete_path
echo $fish_complete_path

# create a symbolic link
ln -s /Library/Frameworks/CarthageKit.framework/Versions/A/Scripts/carthage-fish-completion /path/to/fpath/directory/carthage.fish
```
