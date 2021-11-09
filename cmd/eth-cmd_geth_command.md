### cmd包下的geth子包主函数启动的各个子命令解析

#### /geth

* __init__
```
  function:导入创世块的json,以指定的json作为创世块
  args:<genesisPath>
  demo: init /home/yujian/eth-go/genesis.json
  notice:ethereum默认创建路径为home目录的.ethereum,如果该目录下已经写入过创世快，会执行失败
  success_result_demo:
    WARN [01-16|10:25:12] No etherbase set and no accounts found as default
    INFO [01-16|10:25:12] Allocated cache and file handles         database=/home/yujian/.ethereum/geth/chaindata cache=16 handles=16
    INFO [01-16|10:25:12] Writing custom genesis block
    INFO [01-16|10:25:12] Successfully wrote genesis state         database=chaindata                             hash=bf2891…ad1419
    INFO [01-16|10:25:12] Allocated cache and file handles         database=/home/yujian/.ethereum/geth/lightchaindata cache=16 handles=16
    INFO [01-16|10:25:12] Writing custom genesis block
    INFO [01-16|10:25:12] Successfully wrote genesis state         database=lightchaindata                             hash=bf2891…ad1419
```

* __import__
```
  function:导入区块数据到当前运行的链中
  args:<filename> (<filename 2> ... <filename N>)
  demo: import /home/yujian/eth-block.txt
  notice:如果导入的文件只要一个是错误的，那么会失败，如果有多个文件错误，那么程序会继续执行忽略错误的．
  success_result_demo:
    WARN [01-16|11:00:32] No etherbase set and no accounts found as default
    INFO [01-16|11:00:32] Allocated cache and file handles         database=/home/yujian/.ethereum/geth/chaindata cache=128 handles=1024
    Import done in 306.866µs.

    INFO [01-16|11:00:32] Disk storage enabled for ethash caches   dir=/home/yujian/.ethereum/geth/ethash count=3
    Compactions
    INFO [01-16|11:00:32] Disk storage enabled for ethash DAGs     dir=/home/yujian/.ethash               count=2
     Level |   Tables   |    Size(MB)   |    Time(sec)  |    Read(MB)   |   Write(MB)
    -------+------------+---------------+---------------+---------------+---------------
    INFO [01-16|11:00:32] Loaded most recent local header          number=0 hash=bf2891…ad1419 td=33554432
       0   |          3 |       0.00094 |       0.00000 |       0.00000 |       0.00000
    INFO [01-16|11:00:32] Loaded most recent local full block      number=0 hash=bf2891…ad1419 td=33554432

    Trie cache misses:  0
    INFO [01-16|11:00:32] Loaded most recent local fast block      number=0 hash=bf2891…ad1419 td=33554432
    Trie cache unloads: 0

    INFO [01-16|11:00:32] Importing blockchain                     file=/home/yujian/eth-block.txt
    Object memory: 34.677 MB current, 34.670 MB peak
    System memory: 74.100 MB current, 73.850 MB peak
    Allocations:   0.015 million
    GC pause:      10.454997ms

    Compacting entire database...
    INFO [01-16|11:00:33] Database closed                          database=/home/yujian/.ethereum/geth/chaindata
    Compaction done in 64.422235ms.

    Compactions
     Level |   Tables   |    Size(MB)   |    Time(sec)  |    Read(MB)   |   Write(MB)
    -------+------------+---------------+---------------+---------------+---------------
       0   |          0 |       0.00000 |       0.00451 |       0.00000 |       0.00021
       1   |          1 |       0.00053 |       0.00435 |       0.00114 |       0.00053
```

* __export__
```
  function:导出区块数据到指定的文件
  args:<filename> [<blockNumFirst> <blockNumLast>]
  demo: export /home/yujian/eth-block.txt
  notice:
  success_result_demo:
    WARN [01-16|10:51:36] No etherbase set and no accounts found as default
    INFO [01-16|10:51:36] Allocated cache and file handles         database=/home/yujian/.ethereum/geth/chaindata cache=128 handles=1024
    INFO [01-16|10:51:36] Disk storage enabled for ethash caches   dir=/home/yujian/.ethereum/geth/ethash count=3
    INFO [01-16|10:51:36] Disk storage enabled for ethash DAGs     dir=/home/yujian/.ethash               count=2
    Export done in 628.951µsINFO [01-16|10:51:36] Loaded most recent local header          number=0 hash=bf2891…ad1419 td=33554432
    INFO [01-16|10:51:36] Loaded most recent local full block      number=0 hash=bf2891…ad1419 td=33554432
    INFO [01-16|10:51:36] Loaded most recent local fast block      number=0 hash=bf2891…ad1419 td=33554432
    INFO [01-16|10:51:36] Exporting blockchain                     file=/home/yujian/eth-block.txt
    INFO [01-16|10:51:36] Exporting batch of blocks                count=1
    INFO [01-16|10:51:36] Exported blockchain                      file=/home/yujian/eth-block.txt
```


* __copydb__
```
  function:从存在的链数据文件夹中创建一条本地链
  args:<sourceChaindataDir>
  demo: copydb /home/yujian/eth-block.txt
  notice:
  success_result_demo:
    WARN [01-16|11:35:55] No etherbase set and no accounts found as default
    INFO [01-16|11:35:55] Allocated cache and file handles         database=/home/yujian/.ethereum/geth/chaindata cache=128 handles=1024
    INFO [01-16|11:35:55] Disk storage enabled for ethash caches   dir=/home/yujian/.ethereum/geth/ethash count=3
    INFO [01-16|11:35:55] Disk storage enabled for ethash DAGs     dir=/home/yujian/.ethash               count=2
    INFO [01-16|11:35:55] Loaded most recent local header          number=0 hash=bf2891…ad1419 td=33554432
    INFO [01-16|11:35:55] Loaded most recent local full block      number=0 hash=bf2891…ad1419 td=33554432
    INFO [01-16|11:35:55] Loaded most recent local fast block      number=0 hash=bf2891…ad1419 td=33554432
    INFO [01-16|11:35:55] Allocated cache and file handles         database=/home/yujian/eth-go/geth/chaindata    cache=128 handles=256
    INFO [01-16|11:35:55] Block synchronisation started
    INFO [01-16|11:35:55] Imported new state entries               count=1 elapsed=33.277µs processed=1 pending=0 retry=0 duplicate=0 unexpected=0
    INFO [01-16|11:35:56] Imported new block headers               count=11 elapsed=1.276s   number=11 hash=ec3374…59a2ba ignored=0
    Database copy done in 1.280940454s
    Compacting entire database...
    INFO [01-16|11:35:56] Imported new chain segment               blocks=11 txs=0 mgas=0.000 elapsed=1.961ms  mgasps=0.000 number=11 hash=ec3374…59a2ba
    Compaction done in 11.130389ms.
```

* __removedb__
```
   function:移除当前链的数据库
   args:""
   demo: removedb
   notice:默认当前链的数据在home目录下的.ethereum目录下
   success_result_demo:
     WARN [01-16|11:48:09] No etherbase set and no accounts found as default
     /home/yujian/.ethereum/geth/chaindata
     Remove this database? [y/N] y
     /home/yujian/.ethereum/geth/lightchaindata
     INFO [01-16|11:48:19] Database successfully deleted            database=chaindata elapsed=7.832ms
     Remove this database? [y/N] y
     INFO [01-16|11:48:27] Database successfully deleted            database=lightchaindata elapsed=481.229µs
```


* __dump__
```
   function:转存指定的块
   args:[<blockHash> | <blockNum>]...
   demo: dump 0
   notice:
   success_result_demo:
     "storage": {}
             },
             "af3cb5965933e7dad883693b9c3e15beb68a4873": {
                 "balance": "2000000000000000000000",
                 "nonce": 0,
                 "root": "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
                 "codeHash": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
                 "code": "",
                 "storage": {}
             },
             "af4493e8521ca89d95f5267c1ab63f9f45411e1b": {
                 "balance": "200000000000000000000",
                 "nonce": 0,
                 "root": "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
                 "codeHash": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
                 "code": "",
                 "storage": {}
             },
           }
         }
         INFO [01-16|14:02:06] Database closed                          database=/home/yujian/.ethereum/geth/chaindata
```


* __monitor__
```
    function:监视和可视化节点指标
    args:""
    demo: monitor
    notice:该命令本地未调通,需要先启链，才能调用该命令去看监控的状态
    success_result_demo:
    // TODO



```


* __account__
```
    function:管理账户
    args:"[new|list|update|import]"
    demo: account new
    notice:“帐户导入”选项只能用于导入通用密钥文件
    success_result_demo:
      WARN [01-16|14:44:44] No etherbase set and no accounts found as default
      Your new account is locked with a password. Please give a password. Do not forget this password.
      !! Unsupported terminal, password will be echoed.
      Passphrase: 123456

      Repeat passphrase: 123456

      Address: {2a23e9223d7af9c56f5abd0c8226021b51c98cbc}

      Process finished with exit code 0
```


* __wallet__
```
    function:导入预付款钱包(一般用不到，用的是account功能)
    args:""
    demo: wallet import
    notice:"钱包导入"选项只能用于导入预售钱包
    success_result_demo:

```
　　


* __console__
```
    function:开启一条私有链,并打开一个可视化的js钱包控制台
    args:""
    demo: console
    notice:
    success_result_demo:
      INFO [01-16|15:26:13] Starting peer-to-peer node               instance=Geth/v1.7.3-unstable/linux-amd64/go1.9.2
      INFO [01-16|15:26:13] Allocated cache and file handles         database=/home/yujian/.ethereum/geth/chaindata cache=128 handles=1024
      INFO [01-16|15:26:14] Initialised chain configuration          config="{ChainID: 1 Homestead: 1150000 DAO: 1920000 DAOSupport: true EIP150: 2463000 EIP155: 2675000 EIP158: 2675000 Byzantium: 4370000 Engine: ethash}"
      INFO [01-16|15:26:14] Disk storage enabled for ethash caches   dir=/home/yujian/.ethereum/geth/ethash count=3
      INFO [01-16|15:26:14] Disk storage enabled for ethash DAGs     dir=/home/yujian/.ethash               count=2
      INFO [01-16|15:26:14] Initialising Ethereum protocol           versions="[63 62]" network=1
      INFO [01-16|15:26:14] Loaded most recent local header          number=1127484 hash=ae7ee2…52ae4c td=8985161313979839462
      INFO [01-16|15:26:14] Loaded most recent local full block      number=0       hash=d4e567…cb8fa3 td=17179869184
      INFO [01-16|15:26:14] Loaded most recent local fast block      number=1092806 hash=6e839a…2eb127 td=8395031237882431385
      INFO [01-16|15:26:14] Upgrading chain index                    type=bloombits percentage=80
      INFO [01-16|15:26:14] Loaded local transaction journal         transactions=0 dropped=0
      INFO [01-16|15:26:14] Regenerated local transaction journal    transactions=0 accounts=0
      INFO [01-16|15:26:14] Starting P2P networking
      INFO [01-16|15:26:16] UDP listener up                          self=enode://bef014afb2b63c749d1e3917a25dc9e508cb67e6010965f11695beef50c29f40a5949fc2082487fadb262c30ff2fb626ce86d4a7cf994d025f5dfee7231051e6@[::]:30303
      INFO [01-16|15:26:16] RLPx listener up                         self=enode://bef014afb2b63c749d1e3917a25dc9e508cb67e6010965f11695beef50c29f40a5949fc2082487fadb262c30ff2fb626ce86d4a7cf994d025f5dfee7231051e6@[::]:30303
      INFO [01-16|15:26:16] IPC endpoint opened: /home/yujian/.ethereum/geth.ipc
      Welcome to the Geth JavaScript console!

      instance: Geth/v1.7.3-unstable/linux-amd64/go1.9.2
      coinbase: 0x2a23e9223d7af9c56f5abd0c8226021b51c98cbc
      at block: 0 (Thu, 01 Jan 1970 08:00:00 CST)
       datadir: /home/yujian/.ethereum
       modules: admin:1.0 debug:1.0 eth:1.0 miner:1.0 net:1.0 personal:1.0 rpc:1.0 txpool:1.0 web3:1.0
```



* __attach__
```
    function:打开一个可视化的js钱包控制台(连接到一个指定的链)
    args:
           --jspath loadScript          JavaScript root path for loadScript (default: ".")
           --exec value                 Execute JavaScript statement
           --preload value              Comma separated list of JavaScript files to preload into the console
           --datadir "/root/.ethereum"  Data directory for the databases and keystore
    demo:attach --datadir="/home/yujian/.ethereum/geth.ipc"
    notice:必须启动一条本地链，这样才能连接过去
    success_result_demo:
      Welcome to the Geth JavaScript console!

      instance: Geth/v1.7.3-unstable/linux-amd64/go1.9.2
      coinbase: 0x2a23e9223d7af9c56f5abd0c8226021b51c98cbc
      at block: 0 (Thu, 01 Jan 1970 08:00:00 CST)
       datadir: /home/yujian/.ethereum
       modules: admin:1.0 debug:1.0 eth:1.0 miner:1.0 net:1.0 personal:1.0 rpc:1.0 txpool:1.0 web3:1.0
```

* __js__
```
  　function:执行指定的js文件
    args:<jsfile> [jsfile...]
    demo:js
    notice:
    success_result_demo:



```


* __makecache__

```
   function:生成ethhash验证缓存(测试使用)
   args:<blockNum> <outputDir>
   demo:makecache 0 /home/yujian/
   notice:
   success_result_demo:
     在对应的输出目录，将会生成一个cache文件,如 cache-R23-0000000000000000
```


* __makedag__

```
   function:生成ethhash mining dag(测试使用)
   args:<blockNum> <outputDir>
   demo:makedag 0 /home/yujian/
   notice:
   success_result_demo:
     INFO [01-16|17:50:36] Generating DAG in progress               epoch=0 percentage=92 elapsed=3m2.525s
     INFO [01-16|17:50:38] Generating DAG in progress               epoch=0 percentage=93 elapsed=3m4.338s
     INFO [01-16|17:50:40] Generating DAG in progress               epoch=0 percentage=94 elapsed=3m6.058s
     INFO [01-16|17:50:41] Generating DAG in progress               epoch=0 percentage=95 elapsed=3m7.795s
     INFO [01-16|17:50:43] Generating DAG in progress               epoch=0 percentage=96 elapsed=3m9.542s
     INFO [01-16|17:50:45] Generating DAG in progress               epoch=0 percentage=97 elapsed=3m11.380s
     INFO [01-16|17:50:47] Generating DAG in progress               epoch=0 percentage=98 elapsed=3m13.129s
     INFO [01-16|17:50:49] Generating DAG in progress               epoch=0 percentage=99 elapsed=3m15.303s
     INFO [01-16|17:50:49] Generated ethash verification cache      epoch=0 elapsed=3m15.306s

     Process finished with exit code 0

     在对应的输出目录,将会生成一个full文件,如 full-R23-0000000000000000


```

* __version__

```
   function:打印版本数据
   args:""
   demo:version
   notice:
   success_result_demo:
     Geth
     Version: 1.7.3-unstable
     Architecture: amd64
     Protocol Versions: [63 62]
     Network Id: 1
     Go Version: go1.9.2
     Operating System: linux
     GOPATH=/home/yujian/blockchain-workspace/go-project
     GOROOT=/usr/local/go
   　　
```

* __bug__

```
  function:打开一个窗口,直接跳转到ethereum的github仓库的issue
  args:""
  demo:bug
  notice:
  success_result_demo:
  　　运行后会自动打开浏览器，跳转到ethereum的issue编辑页面　


```

* __license__

```
   function:显示geth的license信息
   args:""
   demo:license
   notice:
   success_result_demo:
      Geth is free software: you can redistribute it and/or modify
      it under the terms of the GNU General Public License as published by
      the Free Software Foundation, either version 3 of the License, or
      (at your option) any later version.

      Geth is distributed in the hope that it will be useful,
      but WITHOUT ANY WARRANTY; without even the implied warranty of
      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
      GNU General Public License for more details.

      You should have received a copy of the GNU General Public License
      along with geth. If not, see <http://www.gnu.org/licenses/>.
```

* __dumpconfig__

```
  function:显示配置信息
  args:""
  demo:dumpconfig
  notice:
  success_result_demo:
  　[Eth]
    NetworkId = 1
    SyncMode = "fast"
    LightPeers = 20
    DatabaseCache = 128
    Etherbase = "0x2a23e9223d7af9c56f5abd0c8226021b51c98cbc"
    GasPrice = 18000000000
    EthashCacheDir = "ethash"
    EthashCachesInMem = 2
    EthashCachesOnDisk = 3
    EthashDatasetDir = "/home/yujian/.ethash"
    EthashDatasetsInMem = 1
    EthashDatasetsOnDisk = 2
    EnablePreimageRecording = false

    [Eth.TxPool]
    NoLocals = false
    Journal = "transactions.rlp"
    Rejournal = 3600000000000
    PriceLimit = 1
    PriceBump = 10
    AccountSlots = 16
    GlobalSlots = 4096
    AccountQueue = 64
    GlobalQueue = 1024
    Lifetime = 10800000000000

    [Eth.GPO]
    Blocks = 10
    Percentile = 50

    [Shh]
    MaxMessageSize = 1048576
    MinimumAcceptedPOW = 2e-01

    [Node]
    DataDir = "/home/yujian/.ethereum"
    IPCPath = "geth.ipc"
    HTTPPort = 8545
    HTTPModules = ["net", "web3", "eth", "shh"]
    WSPort = 8546
    WSModules = ["net", "web3", "eth", "shh"]

    [Node.P2P]
    MaxPeers = 25
    NoDiscovery = false
    DiscoveryV5Addr = ":30304"
    BootstrapNodes = ["enode://a979fb575495b8d6db44f750317d0f4622bf4c2aa3365d6af7c284339968eef29b69ad0dce72a4d8db5ebb4968de0e3bec910127f134779fbcb0cb6d3331163c@52.16.188.185:30303", "enode://3f1d12044546b76342d59d4a05532c14b85aa669704bfe1f864fe079415aa2c02d743e03218e57a33fb94523adb54032871a6c51b2cc5514cb7c7e35b3ed0a99@13.93.211.84:30303", "enode://78de8a0916848093c73790ead81d1928bec737d565119932b98c6b100d944b7a95e94f847f689fc723399d2e31129d182f7ef3863f2b4c820abbf3ab2722344d@191.235.84.50:30303", "enode://158f8aab45f6d19c6cbf4a089c2670541a8da11978a2f90dbf6a502a4a3bab80d288afdbeb7ec0ef6d92de563767f3b1ea9e8e334ca711e9f8e2df5a0385e8e6@13.75.154.138:30303", "enode://1118980bf48b0a3640bdba04e0fe78b1add18e1cd99bf22d53daac1fd9972ad650df52176e7c7d89d1114cfef2bc23a2959aa54998a46afcf7d91809f0855082@52.74.57.123:30303", "enode://979b7fa28feeb35a4741660a16076f1943202cb72b6af70d327f053e248bab9ba81760f39d0701ef1d8f89cc1fbd2cacba0710a12cd5314d5e0c9021aa3637f9@5.1.83.226:30303"]
    BootstrapNodesV5 = ["enode://0cc5f5ffb5d9098c8b8c62325f3797f56509bff942704687b6530992ac706e2cb946b90a34f1f19548cd3c7baccbcaea354531e5983c7d1bc0dee16ce4b6440b@40.118.3.223:30305", "enode://1c7a64d76c0334b0418c004af2f67c50e36a3be60b5e4790bdac0439d21603469a85fad36f2473c9a80eb043ae60936df905fa28f1ff614c3e5dc34f15dcd2dc@40.118.3.223:30308", "enode://85c85d7143ae8bb96924f2b54f1b3e70d8c4d367af305325d30a61385a432f247d2c75c45c6b4a60335060d072d7f5b35dd1d4c45f76941f62a4f83b6e75daaf@40.118.3.223:30309"]
    StaticNodes = []
    TrustedNodes = []
    ListenAddr = ":30303"
    EnableMsgEvents = false

    [Dashboard]
    Host = "localhost"
    Port = 8080
    Refresh = 3000000000　
```


##### 参考资料
  * [eth钱包创建](https://www.myetherwallet.com/#generate-wallet)
  * [eth命令使用解释](http://www.blockcode.org/archives/185)


