# dotfiles

## いつもの

windyakin さんの dotfiles を自分用に改変しました．

## Quick Start!

お試しでDockerコンテナ上に私の開発環境を構築できます。

### on Docker Host

Docker ホスト上で立ち上げるには以下のコマンド

```
$ docker run -it --rm windyakin/dotfiles
```

### on Docker Container (Option)

履歴検索などシェルに関連付けされているすべての機能を使用するには Linuxbrew から以下のソフトウェアをインストールします。

```
$ brew install peco tig rbenv nodebrew
```

### 実環境

```sh
sudo apt-get update
sudo apt-get dist-upgrade -y
sudo apt-get install -y sudo git zsh software-properties-common build-essential curl file python-setuptools ruby
sudo rm -rf /var/lib/apt/lists/*

sudo chsh -s /bin/zsh

sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"

test -d ~/.linuxbrew && PATH="$HOME/.linuxbrew/bin:$HOME/.linuxbrew/sbin:$PATH"
test -d /home/linuxbrew/.linuxbrew && PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
test -r ~/.bash_profile && echo "export PATH='$(brew --prefix)/bin:$(brew --prefix)/sbin'":'"$PATH"' >>~/.bash_profile
echo "export PATH='$(brew --prefix)/bin:$(brew --prefix)/sbin'":'"$PATH"' >>~/.profile

brew install peco tig rbenv nodebrew

./dotfiles/setup.sh
```

## Thanks

* windyakin ([@MITLicense](https://twitter.com/MITLicense))
