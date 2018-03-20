
##  go-ethereum源码解析
因为go ethereum是最被广泛使用的以太坊客户端， 所以后续的源码分析都从github上面的这份代码进行分析。 

### 搭建go ethereum调试环境

#### windows 10 64bit
首先下载go安装包进行安装，因为GO的网站被墙，所以从下面地址下载。

	https://studygolang.com/dl/golang/go1.9.1.windows-amd64.msi

安装好之后，设置环境变量，把C:\Go\bin目录添加到你的PATH环境变量， 然后增加一个GOPATH的环境变量，GOPATH的值设置为你的GO语言下载的代码路径(我设置的是C:\GOPATH)

![image](https://raw.githubusercontent.com/wugang33/go-ethereum-code-analysis/master/picture/go_env_1.png)

安装git工具，请参考网络上的教程安装git工具， go语言从github自动下载代码需要git工具的支持

打开命令行工具下载 go-ethereum的代码
	
	go get github.com/ethereum/go-ethereum

命令执行成功之后，代码就会下载到下面这个目录，%GOPATH%\src\github.com\ethereum\go-ethereum
如果执行过程中出现

	# github.com/ethereum/go-ethereum/crypto/secp256k1
	exec: "gcc": executable file not found in %PATH%

则需要安装gcc工具，我们从下面地址下载并安装

	http://tdm-gcc.tdragon.net/download

接下来安装IDE工具。 我是用的IDE是JetBrains的Gogland。 可以在下面地址下载

	https://download.jetbrains.com/go/gogland-173.2696.28.exe

安装完成后打开IDE. 选择File -> Open -> 选择GOPATH\src\github.com\ethereum\go-ethereum目录打开。

然后打开go-ethereum/rlp/decode_test.go. 在编辑框右键选择运行， 如果运行成功，代表环境搭建完成。

![image](https://raw.githubusercontent.com/wugang33/go-ethereum-code-analysis/master/picture/go_env_2.png)

### Ubuntu 16.04 64bit
 
go安装包进行安装

	apt install golang-go git -y

golang环境配置：

	编辑/etc/profile文件，在该文件中加入以下内容：
	export GOROOT=/usr/bin/go  
	export GOPATH=/root/home/goproject
	export GOBIN=/root/home/goproject/bin
	export GOLIB=/root/home/goproject/
	export PATH=$PATH:$GOBIN:$GOPATH/bin:$GOROOT/bin
执行以下命令，使得环境变量生效：<br/>
	
	# source /etc/profile

下载源码：
	
	#cd  /root/home/goproject; mkdir src； cd src  #进入go项目目录，并创建src目录, 并进入src目录
	#git clone https://github.com/ethereum/go-ethereum

使用vim或其他IDE打开即可；


### go ethereum 目录大概介绍
go-ethereum项目的组织结构基本上是按照功能模块划分的目录，下面简单介绍一下各个目录的结构，每个目录在GO语言里面又被成为一个Package,我理解跟Java里面的Package应该是差不多的意思。


	accounts        	实现了一个高等级的以太坊账户管理
	bmt			二进制的默克尔树的实现
	build			主要是编译和构建的一些脚本和配置
	cmd			命令行工具，又分了很多的命令行工具，下面一个一个介绍
		/abigen		Source code generator to convert Ethereum contract definitions into easy to use, compile-time type-safe Go packages
		/bootnode	启动一个仅仅实现网络发现的节点
		/evm		以太坊虚拟机的开发工具， 用来提供一个可配置的，受隔离的代码调试环境
		/faucet		
		/geth		以太坊命令行客户端，最重要的一个工具
		/p2psim		提供了一个工具来模拟http的API
		/puppeth	创建一个新的以太坊网络的向导
		/rlpdump 	提供了一个RLP数据的格式化输出
		/swarm		swarm网络的接入点
		/util		提供了一些公共的工具
		/wnode		这是一个简单的Whisper节点。 它可以用作独立的引导节点。此外，可以用于不同的测试和诊断目的。
	common			提供了一些公共的工具类
	compression		Package rle implements the run-length encoding used for Ethereum data.
	consensus		提供了以太坊的一些共识算法，比如ethhash, clique(proof-of-authority)
	console			console类
	contracts	
	core			以太坊的核心数据结构和算法(虚拟机，状态，区块链，布隆过滤器)
	crypto			加密和hash算法，
	eth			实现了以太坊的协议
	ethclient		提供了以太坊的RPC客户端
	ethdb			eth的数据库(包括实际使用的leveldb和供测试使用的内存数据库)
	ethstats		提供网络状态的报告
	event			处理实时的事件
	les			实现了以太坊的轻量级协议子集
	light			实现为以太坊轻量级客户端提供按需检索的功能
	log			提供对人机都友好的日志信息
	metrics			提供磁盘计数器
	miner			提供以太坊的区块创建和挖矿
	mobile			移动端使用的一些warpper
	node			以太坊的多种类型的节点
	p2p			以太坊p2p网络协议
	rlp			以太坊序列化处理
	rpc			远程方法调用
	swarm			swarm网络处理
	tests			测试
	trie			以太坊重要的数据结构Package trie implements Merkle Patricia Tries.
	whisper			提供了whisper节点的协议。

可以看到以太坊的代码量还是挺大的，但是粗略看，代码结构还是挺好的。我希望先从一些比较独立的模块来进行分析。然后在深入分析内部的代码。重点可能集中在黄皮书里面没有涉及到的p2p网络等模块。
