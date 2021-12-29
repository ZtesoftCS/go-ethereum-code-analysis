---
title: "开始"
weight: 90001
---

欢迎勇敢的你！

## 以太坊版本说明

为保持一致的源代码讲解环境，推荐在本地签出 git commit `bca140` 代码进行查看。命令如下：

首先，创建文件夹存放源代码：

```bash
mkdir -p $GOPATH/src/github.com/ethereum/go-ethereum
```

再从Github下载以太坊Go-ethereum项目源代码：

```bash
cd $GOPATH/src/github.com/ethereum/go-ethereum
git clone https://github.com/ethereum/go-ethereum.git  ./
```

下载成功后，利用 git commit 创建新分支 `deepeth`：

```bash
 git checkout -b deepeth bca140
```

当你切换分支成功后，看到命令行最后一行信息应该是：

```text
Switched to a new branch 'deepeth'
```

## 编译geth

为降低沟通成本，请在本机准备好随时可使用的 geth 可执行程序。

1. 打开 go-ethereum 目录

    ```bash
    cd $GOPATH/src/github.com/ethereum/go-ethereum
    ```

1. 编译 go-ethereum

    ```bash
    make
    # output:
    #   Done building.
    #   Run: "$GOPATH/src/github.com/ethereum/go-ethereum/build/bin/geth" to launch geth.
    ```

    注意：命令是在 Mac 环境下执行，如果是 Windows 电脑，则有所差异，下同。

1. 拷贝可执行程序

    ```bash
    mv $GOPATH/src/github.com/ethereum/go-ethereum/build/bin/geth $GOPATH/bin/dgeth
    ```

    Go 开发中，一般环境变量 `$GOPATH` 均有设置，且 `$GOPATH/bin` 目录也会加入环境变量，方便命令行直接执行可执行程序。
因此 geth 执行程序也重命名为 dgeth 存放至此。

1. 检查文件

    ```bash
    dgeth version
    # output:
    #   Geth
    #   Version: 1.9.0-unstable
    #   Git Commit: bca140b73dc107676c912d87f6fe9c352d5fd0d8
    ```