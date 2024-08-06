# Dotfiles

This repository aims to store my dotfiles configurations with the help of GNU Stow, so I can have a seamless shell experience across multiple machines with different Operational Systems

## Getting Started

First of all, you'll need to setup your SSH key for GitHub, since all `git clone` commands ran for this configuration use the ssh URL.

After that, you'll need to install some packages, depending on your SO:

```shell
# For Linux(Ubuntu based distros)
sudo apt install zsh git stow fzf
# For MacOS
brew install zsh git stow fzf coreutils
```

If you're running on Linux, install also [homebrew](https://homebrew.sh):

```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After that, you can clone this repository into your home:

```shell
git clone git@github.com:Alba-22/dotfiles.git
```

Then, go to the `dotfiles` directory and set stow to that directory

```shell
cd dotfiles
stow .
```

Now, get back to your home directory and set your terminal to use zsh as its default shell

```shell
chsh -s $(which zsh)
```

After that check if your terminal emulator did set the zsh as the default shell correctly, by running the following command:

```shell
echo $0
# or
echo $SHELL
```

Now, restart your terminal emulator and, if everything runs as expected, your shell will be good to go, with zinit plugin managers installing everything you'll need :D
