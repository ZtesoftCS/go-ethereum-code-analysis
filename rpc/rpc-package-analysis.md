## RPC包概述
RPC包主要的服务逻辑在server.go和subscription.go包中。接口的定义在types.go中。<br>
RPC包主要实现在启动节点的时候，将自己写的api包通过反射的形式将方法名和调用的api绑定。在启动命令行之后，通过输入命令的形式，通过RPC方法找到对应的方法调用，获取返回值。<br>
## RPC方法追踪
首先，在geth启动时，geth中有startNode方法，通过层层跟踪我们进入到了Node.Start()方法中。<br>
在start方法中，有一个startRPC方法，启动节点的RPC。<br>
```go
// startRPC is a helper method to start all the various RPC endpoint during node
// startup. It's not meant to be called at any time afterwards as it makes certain
// assumptions about the state of the node.
    func (n *Node) startRPC(services map[reflect.Type]Service) error {
        // Gather all the possible APIs to surface
        apis := n.apis()
        for _, service := range services {
            apis = append(apis, service.APIs()...)
        }
        // Start the various API endpoints, terminating all in case of errors
        if err := n.startInProc(apis); err != nil {
            return err
        }
        if err := n.startIPC(apis); err != nil {
            n.stopInProc()
            return err
        }
        if err := n.startHTTP(n.httpEndpoint, apis, n.config.HTTPModules, n.config.HTTPCors); err != nil {
            n.stopIPC()
            n.stopInProc()
            return err
        }
        if err := n.startWS(n.wsEndpoint, apis, n.config.WSModules, n.config.WSOrigins, n.config.WSExposeAll); err != nil {
            n.stopHTTP()
            n.stopIPC()
            n.stopInProc()
            return err
        }
        // All API endpoints started successfully
        n.rpcAPIs = apis
        return nil
    }
```
这里，startRPC方法在执行时就会去读取api，然后暴露各个api。<br>
apis()的定义如下：
```go
// apis returns the collection of RPC descriptors this node offers.
    func (n *Node) apis() []rpc.API {
        return []rpc.API{
            {
                Namespace: "admin",
                Version:   "1.0",
                Service:   NewPrivateAdminAPI(n),
            }, {
                Namespace: "admin",
                Version:   "1.0",
                Service:   NewPublicAdminAPI(n),
                Public:    true,
            }, {
                Namespace: "debug",
                Version:   "1.0",
                Service:   debug.Handler,
            }, {
                Namespace: "debug",
                Version:   "1.0",
                Service:   NewPublicDebugAPI(n),
                Public:    true,
            }, {
                Namespace: "web3",
                Version:   "1.0",
                Service:   NewPublicWeb3API(n),
                Public:    true,
            },
        }
    }
```
其中，Namespace是我们定义的包名，即在命令行中可以调用的方法。<br>
Version是这个包的版本号。
Service是所映射的API管理的结构体，这里API的方法需要满足RPC的标准才能通过校验。<br>
成为RPC调用方法标准如下：<br>
```markdown
    ·对象必须导出<br>
    ·方法必须导出<br>
    ·方法返回0，1（响应或错误）或2（响应和错误）值<br>
    ·方法参数必须导出或是内置类型<br>
    ·方法返回值必须导出或是内置类型<br>
```
在将各个API都写入到列表中之后，然后启动多个API endpoints。<br>
这里我们以启动IPC为例，主要看startIPC方法。<br>
```go
    func (n *Node) startIPC(apis []rpc.API) error {
        // Short circuit if the IPC endpoint isn't being exposed
        if n.ipcEndpoint == "" {
            return nil
        }
        // Register all the APIs exposed by the services
        handler := rpc.NewServer()
        for _, api := range apis {
            if err := handler.RegisterName(api.Namespace, api.Service); err != nil {
                return err
            }
            n.log.Debug(fmt.Sprintf("IPC registered %T under '%s'", api.Service, api.Namespace))
        }
    ...
```
这里会首先启创建一个rpc server。在启动的过程中，rpc server会将自己注册到handler中，即rpc包。<br>
在创建rpc server之后，handler会通过RegisterName方法将暴露的方法注册到rpc server中。<br>
```go
// RegisterName will create a service for the given rcvr type under the given name. When no methods on the given rcvr
// match the criteria to be either a RPC method or a subscription an error is returned. Otherwise a new service is
// created and added to the service collection this server instance serves.
    func (s *Server) RegisterName(name string, rcvr interface{}) error {
        if s.services == nil {
            s.services = make(serviceRegistry)
        }
    
        svc := new(service)
        svc.typ = reflect.TypeOf(rcvr)
        rcvrVal := reflect.ValueOf(rcvr)
    
        if name == "" {
            return fmt.Errorf("no service name for type %s", svc.typ.String())
        }
        if !isExported(reflect.Indirect(rcvrVal).Type().Name()) {
            return fmt.Errorf("%s is not exported", reflect.Indirect(rcvrVal).Type().Name())
        }
    
        methods, subscriptions := suitableCallbacks(rcvrVal, svc.typ)
        // already a previous service register under given sname, merge methods/subscriptions
    	if regsvc, present := s.services[name]; present {
    		if len(methods) == 0 && len(subscriptions) == 0 {
    			return fmt.Errorf("Service %T doesn't have any suitable methods/subscriptions to expose", rcvr)
    		}
    		for _, m := range methods {
    			regsvc.callbacks[formatName(m.method.Name)] = m
    		}
    		for _, s := range subscriptions {
    			regsvc.subscriptions[formatName(s.method.Name)] = s
    		}
    		return nil
    	}
    
    	svc.name = name
    	svc.callbacks, svc.subscriptions = methods, subscriptions
    
    	if len(svc.callbacks) == 0 && len(svc.subscriptions) == 0 {
    		return fmt.Errorf("Service %T doesn't have any suitable methods/subscriptions to expose", rcvr)
    	}
    
    	s.services[svc.name] = svc
    	return nil
    }
```
在RegisterName方法中，这个方法会将所提供包下所有符合RPC调用标准的方法注册到Server的callback调用集合中等待调用。<br>
这里，筛选符合条件的RPC调用方法又suitableCallbacks方法实现。<br>
这样就将对应包中的方法注册到Server中，在之后的命令行中即可调用。<br>
## 参考资料
[RPC包的官方文档](https://github.com/qewetfty/ethereum-analysis/blob/master/go-ethereum-code-analysis/rpc源码分析.md)