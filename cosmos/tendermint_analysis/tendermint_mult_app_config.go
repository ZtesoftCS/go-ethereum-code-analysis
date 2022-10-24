
// 第二个tendermint 启动时，添加第二个app config

//cosmos sdk : server/util.go

// server context
type Context struct {
	Config *cfg.Config
	Config2 *cfg.Config
	Logger log.Logger
}

func NewDefaultContext() *Context {
	return NewContext(
		cfg.DefaultConfig(),
		cfg.DefaultConfig(),
		log.NewTMLogger(log.NewSyncWriter(os.Stdout)),
	)
}

func PersistentPreRunEFn(context *Context) func(*cobra.Command, []string) error {
	return func(cmd *cobra.Command, args []string) error {
		if cmd.Name() == version.Cmd.Name() {
			return nil
		}
		config, err := interceptLoadConfig()
		config2, err := interceptLoadConfig2()
	
		if err != nil {
			return err
		}
		logger := log.NewTMLogger(log.NewSyncWriter(os.Stdout))
		logger, err = tmflags.ParseLogLevel(config.LogLevel, logger, cfg.DefaultLogLevel())
		if err != nil {
			return err
		}
		if viper.GetBool(cli.TraceFlag) {
			logger = log.NewTracingLogger(logger)
		}
		logger = logger.With("module", "main")
		context.Config = config
		context.Config2 = config2
		context.Logger = logger
		return nil
	}
}

func interceptLoadConfig2() (conf *cfg.Config, err error) {
	tmpConf := cfg.DefaultConfig()
	err = viper.Unmarshal(tmpConf)
	if err != nil {
		// TODO: Handle with #870
		panic(err)
	}
	// todo flag
	tmpConf.SetRoot("/Users/haierding/.nsd2")
	rootDir := tmpConf.RootDir // config2

	configFilePath := filepath.Join(rootDir, "config/config.toml")
	// Intercept only if the file doesn't already exist

	if _, err := os.Stat(configFilePath); os.IsNotExist(err) {
		// the following parse config is needed to create directories
		conf, _ = tcmd.ParseConfig() // NOTE: ParseConfig() creates dir/files as necessary.
		conf.ProfListenAddress = "localhost:36060"
		conf.P2P.RecvRate = 5120000
		conf.P2P.SendRate = 5120000
		conf.TxIndex.IndexAllKeys = true
		conf.Consensus.TimeoutCommit = 5 * time.Second
		cfg.WriteConfigFile(configFilePath, conf)
		// Fall through, just so that its parsed into memory.
	}

	if conf == nil {
		conf, err = tcmd.ParseConfig() // NOTE: ParseConfig() creates dir/files as necessary.
		conf.SetRoot(tmpConf.RootDir)
		if err != nil {
			panic(err)
		}
	}

	appConfigFilePath := filepath.Join(rootDir, "config/app.toml")
	if _, err := os.Stat(appConfigFilePath); os.IsNotExist(err) {
		appConf, _ := config.ParseConfig()
		config.WriteConfigFile(appConfigFilePath, appConf)
	}
	
	viper.SetConfigName("app")
	err = viper.MergeInConfig()

	return conf, err
}