### cmd包分析
#### cmd下面总共有13个子包，除了util包之外，每个子包都有一个主函数,每个主函数的init方法中都定义了该主函数支持的命令，如

##### geth包下面的：

```
func init() {
	// Initialize the CLI app and start Geth
	app.Action = geth
	app.HideVersion = true // we have a command to print the version
	app.Copyright = "Copyright 2013-2017 The go-ethereum Authors"
	app.Commands = []cli.Command{
		// See chaincmd.go:
		initCommand,
		importCommand,
		exportCommand,
		copydbCommand,
		removedbCommand,
		dumpCommand,
		// See monitorcmd.go:
		monitorCommand,
		// See accountcmd.go:
		accountCommand,
		walletCommand,
		// See consolecmd.go:
		consoleCommand,
		attachCommand,
		javascriptCommand,
		// See misccmd.go:
		makecacheCommand,
		makedagCommand,
		versionCommand,
		bugCommand,
		licenseCommand,
		// See config.go
		dumpConfigCommand,
	}
	sort.Sort(cli.CommandsByName(app.Commands))
}
```


###### 再单独分析initCommand:

```
initCommand = cli.Command{
      Action:    utils.MigrateFlags(initGenesis),
      Name:      "init",
      Usage:     "Bootstrap and initialize a new genesis block",
      ArgsUsage: "<genesisPath>",
      Flags: []cli.Flag{
         utils.DataDirFlag,
         utils.LightModeFlag,
      },
      Category: "BLOCKCHAIN COMMANDS",
      Description: `
The init command initializes a new genesis block and definition for the network.
This is a destructive action and changes the network in which you will be
participating.

```

###### 其中Name是对应命令的指令，action是调用该指令去完成的动作，usage表示用途,arguUsage显示该命令后面跟的参数个数以及每个参数的意义,
###### 该init方法其实就是去初始化创世块,flags代表的是这个子命令额外可以执行的命令,如改init命令可以携带两个参数，点进去utils.DataDirFlag可以看到：

```
// General settings
DataDirFlag = DirectoryFlag{
   Name:  "datadir",
   Usage: "Data directory for the databases and keystore",
   Value: DirectoryString{node.DefaultDataDir()},
}
```


* __可以用 --datadir [dir]来指定数据库的路径，如果没有指定由于该参数有value所以会启用默认的路径，也是home目录下面的.ethereum.__

*  __/cmd/wnode/main.go　通过连接其他节点启动__


*  __/cmd/geth /cmd/swarm　都是定义了很多命令__
