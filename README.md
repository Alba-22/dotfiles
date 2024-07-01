# Dotfiles
This repository aims to store my dotfiles configurations with the help of GNU Stow, so I can have a seamless shell experience across multiple machines with different Operational Systems

## Getting Started
First of all, you'll need to install the following packages, with the help of your package manager:
```shell
sudo apt install zsh git stow fzf
```

After that, you can clone this repository into your home:
```shell
git clone git@github.com:Alba-22/dotfiles.git ## Or use HTTPS if you prefer
```

Then, go to the `dotfiles` folder and set stow to that folder
```shell
cd dotfiles
stow .
```

Now, get back to your home folder and set your terminal to use zsh as its default shell
```shell
chsh -s $(which zsh)
source .zshrc
```

So, if everything runs as expected, your shell will be good to go, with zinit plugin managers installing everything you'll need :D
