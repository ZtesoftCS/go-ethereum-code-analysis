### cmd包下的p2psim子包的分析, p2psim is a command line client for the HTTP API

##### 首先我们启动对应的main函数,对应的启动参数是`--help`,来查看该包下所有命令的使用,结果如下:

```
NAME:
   ___go_build_main_go__1_ - devp2p simulation command-line client

USAGE:
   ___go_build_main_go__1_ [global options] command [command options] [arguments...]

VERSION:
   0.0.0

COMMANDS:
     show      show network information
     events    stream network events
     snapshot  create a network snapshot to stdout
     load      load a network snapshot from stdin
     node      manage simulation nodes
     help, h   Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --api value    simulation API URL (default: "http://localhost:8888") [$P2PSIM_API_URL]
   --help, -h     show help
   --version, -v  print the version
```

##### 该子包提供如何下的命令:
```
p2psim show
p2psim events [--current] [--filter=FILTER]
p2psim snapshot
p2psim load
p2psim node create [--name=NAME] [--services=SERVICES] [--key=KEY]
p2psim node list
p2psim node show <node>
p2psim node start <node>
p2psim node stop <node>
p2psim node connect <node> <peer>
p2psim node disconnect <node> <peer>
p2psim node rpc <node> <method> [<args>] [--subscribe]

```

##### 要正常使用该子包下的命令，我们需要运行`/p2p/simulations/examples/ping-pong.go`的主函数来启动一个包含运行简单的节点的仿真网络.
正常启动后,你将看到:
```
INFO [01-23|11:17:10] using sim adapter
INFO [01-23|11:17:10] starting simulation server on 0.0.0.0:8888...

```

##### 该服务启动后,提供如下的API,其作用等同于上面的命令,命令调用的实现其实就是调用API,访问的路径前缀就是`0.0.0.0:8888`:
```
GET    /                            Get network information
POST   /start                       Start all nodes in the network
POST   /stop                        Stop all nodes in the network
GET    /events                      Stream network events
GET    /snapshot                    Take a network snapshot
POST   /snapshot                    Load a network snapshot
POST   /nodes                       Create a node
GET    /nodes                       Get all nodes in the network
GET    /nodes/:nodeid               Get node information
POST   /nodes/:nodeid/start         Start a node
POST   /nodes/:nodeid/stop          Stop a node
POST   /nodes/:nodeid/conn/:peerid  Connect two nodes
DELETE /nodes/:nodeid/conn/:peerid  Disconnect two nodes
GET    /nodes/:nodeid/rpc           Make RPC requests to a node via WebSocket

```

##### 此处不深究API,仿真网络的服务已经起来了,下面开始p2psim包下命令的使用:

__/p2psim__

 * show
 ```
   function:显示当前仿真网络的状态
   args:""
   demo: show
   notice:
   success_result_demo:
     NODES  0
     CONNS  0

 ```

 * snapshot
  ```
    function:导出当前仿真网络的节点信息
    args:""
    demo: shapshot
    notice:
    success_result_demo:
      {"nodes":[{"node":{"config":{"id":"085416957c3a0afef6aabe6c0d6b27b7cf8a61f28a3a5439010fcc9e49945a1818ea38946dda8c82004b231ab771450ee0d87886163b65eaa48ecfbcb85e871d","private_key":"3480d230f453e7c207bbd3b770bf774dc8a17e599394f9283147a35c3ead561c","name":"node1","services":["ping-pong"]},"up":true}},{"node":{"config":{"id":"cedbaecccfe42d04b742d1be6e924e0654a7eb1aa584d497f98d24951b156ada84bcfc6455ff37ba1fc81179d0a7c3da1ba34945be19d1fe5cd4c8a32a659a7b","private_key":"b7592cdeee6195c4486fcdd8007e1aedfd3a49e6c9f53e0845bf977d4ad043cc","name":"node2","services":["ping-pong"]},"up":false}}],"conns":[{"one":"cedbaecccfe42d04b742d1be6e924e0654a7eb1aa584d497f98d24951b156ada84bcfc6455ff37ba1fc81179d0a7c3da1ba34945be19d1fe5cd4c8a32a659a7b","other":"085416957c3a0afef6aabe6c0d6b27b7cf8a61f28a3a5439010fcc9e49945a1818ea38946dda8c82004b231ab771450ee0d87886163b65eaa48ecfbcb85e871d","up":false}]}


  ```

 * node
  > * create
  ```
     function:创建一个节点
     args:[--name=NAME] [--services=SERVICES] [--key=KEY]
     demo: node create --name node1
     notice:
     success_result_demo:
       Created node1
  ```
  > * list
  ```
     function:列出当前仿真网络的节点信息
     args:""
     demo: node list
     notice:
     success_result_demo:
       NAME   PROTOCOLS  ID
       node1             085416957c3a0afef6aabe6c0d6b27b7cf8a61f28a3a5439010fcc9e49945a1818ea38946dda8c82004b231ab771450ee0d87886163b65eaa48ecfbcb85e871d
       node2             cedbaecccfe42d04b742d1be6e924e0654a7eb1aa584d497f98d24951b156ada84bcfc6455ff37ba1fc81179d0a7c3da1ba34945be19d1fe5cd4c8a32a659a7b

  ```
  > * show
  ```
    function:查看仿真网络中某个节点的具体信息
    args:<node>
    demo: node show node1
    notice:
    success_result_demo:
      NAME       node1
      PROTOCOLS
      ID         085416957c3a0afef6aabe6c0d6b27b7cf8a61f28a3a5439010fcc9e49945a1818ea38946dda8c82004b231ab771450ee0d87886163b65eaa48ecfbcb85e871d
      ENODE      enode://085416957c3a0afef6aabe6c0d6b27b7cf8a61f28a3a5439010fcc9e49945a1818ea38946dda8c82004b231ab771450ee0d87886163b65eaa48ecfbcb85e871d@127.0.0.1:30303
  ```
  > * start
  ```
     function:启动一个节点
     args:<node>
     demo: node start node1
     notice:
     success_result_demo:
       Started node1
  ```
  > * connect
  ```
     function:将一个节点连接到另外一个节点
     args:<node> <peer>
     demo: node connect node2 node1
     notice:
     success_result_demo:
       Connected node2 to node1

  ```
  > * disconnect

    ```
       function:节点断开连接
       args:<node> <peer>
       demo: node disconnect node2 node1
       notice:
       success_result_demo:
         Disconnected node2 from node1

    ```
  > * stop

     ```
       function:停止一个节点
       args:<node>
       demo: node stop node2
       notice:
       success_result_demo:
         Stopped node2

     ```
   > * rpc

      ```
         function:调用rpc接口
         args:<node> <method> [<args>] [--subscribe]
         demo: node rpc node1 admin
         notice:
         success_result_demo:
          　// TODO

       ```

##### 参考资料
  * __[P2Psim分析笔记(7)-RPC机制](http://www.cto800.com/view/39301865167033790007.html)__
  * __[ethereum rpc package](https://gowalker.org/github.com/ethereum/go-ethereum/rpc?refs)__









