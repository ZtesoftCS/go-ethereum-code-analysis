# 封装的一些基础工具
在[以太坊](https://github.com/ethereum/go-ethereum)项目中，存在对golang生态体系中一些优秀工具进行封装的小模块，由于功能较为单一，单独成篇显得过于单薄。但是由于以太坊对这些小工具的封装非常优雅，具有很强的独立性和实用性。我们在此作一些分析，至少对于熟悉以太坊源码的编码方式是有帮助的。
## metrics（探针）
在[ethdb源码分析](/ethdb源码分析.md)中，我们看到了对[goleveldb](https://github.com/syndtr/goleveldb)项目的封装。ethdb除了对goleveldb抽象了一层：

[type Database interface](https://github.com/ethereum/go-ethereum/blob/master/ethdb/interface.go#L29)

以支持与MemDatabase的同接口使用互换外，还在LDBDatabase中使用很多[gometrics](https://github.com/rcrowley/go-metrics)包下面的探针工具，以及能启动一个goroutine执行

[go db.meter(3 * time.Second)](https://github.com/ethereum/go-ethereum/blob/master/ethdb/database.go#L198)

以3秒为周期，收集使用goleveldb过程中的延时和I/O数据量等指标。看起来很方便，但问题是我们如何使用这些收集来的信息呢？

## log（日志）
golang的内置log包一直被作为槽点，而以太坊项目也不例外。故引入了[log15](https://github.com/inconshreveable/log15)以解决日志使用不便的问题。


