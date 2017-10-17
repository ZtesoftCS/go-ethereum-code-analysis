Package rpc provides access to the exported methods of an object across a network
or other I/O connection. After creating a server instance objects can be registered,
making it visible from the outside. Exported methods that follow specific
conventions can be called remotely. It also has support for the publish/subscribe
pattern.

rpc包提供这样一种能力，可以通过网络或者其他I/O连接，可以访问对象被导出的方法。创建一个服务器之后，对象可以注册到服务器上，然后可以让外界访问。通过脂肪方式导出的方法可以被远程调用。 同时还支持发布/订阅模式。

Methods that satisfy the following criteria are made available for remote access:

- object must be exported
- method must be exported
- method returns 0, 1 (response or error) or 2 (response and error) values
- method argument(s) must be exported or builtin types
- method returned value(s) must be exported or builtin types

符合以下标准的方法可用于远程访问：

- 对象必须导出
- 方法必须导出
- 方法返回0，1（响应或错误）或2（响应和错误）值
- 方法参数必须导出或是内置类型
- 方法返回值必须导出或是内置类型

An example method:

	func (s *CalcService) Add(a, b int) (int, error)

When the returned error isn't nil the returned integer is ignored and the error is
send back to the client. Otherwise the returned integer is send back to the client.

当返回的error不等于nil的时候，返回的整形值被忽略，error被发送回客户端。 否则整形的会返回被发送回客户端。

Optional arguments are supported by accepting pointer values as arguments. E.g.
if we want to do the addition in an optional finite field we can accept a mod
argument as pointer value.
通过提供指针类型的参数可以使得方法支持可选参数。后面有点看不懂了。

	 func (s *CalService) Add(a, b int, mod *int) (int, error)

This RPC method can be called with 2 integers and a null value as third argument.
In that case the mod argument will be nil. Or it can be called with 3 integers,
in that case mod will be pointing to the given third argument. Since the optional
argument is the last argument the RPC package will also accept 2 integers as
arguments. It will pass the mod argument as nil to the RPC method.

RPC方法可以通过传两个integer和一个null值作为第三个参数来调用。在这种情况下mod参数会被设置为nil。或者可以传递三个integer,这样mod会被设置为指向第三个参数。尽管可选的参数是最后的参数，RPC包任然接收传递两个integer,这样mod参数会被设置为nil。

The server offers the ServeCodec method which accepts a ServerCodec instance. It will
read requests from the codec, process the request and sends the response back to the
client using the codec. The server can execute requests concurrently. Responses
can be sent back to the client out of order.

server提供了ServerCodec方法，这个方法接收ServerCodec实例作为参数。 服务器会使用codec读取请求，处理请求，然后通过codec发送回应给客户端。server可以并发的执行请求。response的顺序可能和request的顺序不一致。

	//An example server which uses the JSON codec:
	 type CalculatorService struct {}
	
	 func (s *CalculatorService) Add(a, b int) int {
		return a + b
	 }
	
	 func (s *CalculatorService Div(a, b int) (int, error) {
		if b == 0 {
			return 0, errors.New("divide by zero")
		}
		return a/b, nil
	 }
	calculator := new(CalculatorService)
	 server := NewServer()
	 server.RegisterName("calculator", calculator")
	
	 l, _ := net.ListenUnix("unix", &net.UnixAddr{Net: "unix", Name: "/tmp/calculator.sock"})
	 for {
		c, _ := l.AcceptUnix()
		codec := v2.NewJSONCodec(c)
		go server.ServeCodec(codec)
	 }


The package also supports the publish subscribe pattern through the use of subscriptions.
A method that is considered eligible for notifications must satisfy the following criteria:

 - object must be exported
 - method must be exported
 - first method argument type must be context.Context
 - method argument(s) must be exported or builtin types
 - method must return the tuple Subscription, error


该软件包还通过使用订阅来支持发布订阅模式。
被认为符合通知条件的方法必须满足以下条件：

- 对象必须导出
- 方法必须导出
- 第一个方法参数类型必须是context.Context
- 方法参数必须导出或内置类型
- 方法必须返回元组订阅，错误

An example method:

	 func (s *BlockChainService) NewBlocks(ctx context.Context) (Subscription, error) {
	 	...
	 }

Subscriptions are deleted when:

 - the user sends an unsubscribe request
 - the connection which was used to create the subscription is closed. This can be initiated
   by the client and server. The server will close the connection on an write error or when
   the queue of buffered notifications gets too big.

订阅在下面几种情况下会被删除

- 用户发送了一个取消订阅的请求
- 创建订阅的连接被关闭。这种情况可能由客户端或者服务器触发。 服务器在写入出错或者是通知队列长度太大的时候会选择关闭连接。

