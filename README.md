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

## Thanks

* windyakin ([@MITLicense](https://twitter.com/MITLicense))
