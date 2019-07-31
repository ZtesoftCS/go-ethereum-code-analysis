accounts包实现了以太坊客户端的钱包和账户管理。以太坊的钱包提供了keyStore模式和usb两种钱包。同时以太坊的 合约的ABI的代码也放在了account/abi目录。 abi项目好像跟账户管理没有什么关系。 这里暂时只分析了账号管理的接口。 具体的keystore和usb的实现代码暂时不会给出。
# 组件关系
![](https://github.com/Billy1900/go-ethereum-code-analysis/blob/master/picture/accounts.png)
# accounts支持的钱包类型
在accounts中总共支持两大类共4种钱包类型。两大类包括keystore和usbwallet；其中keystore中的私钥存储可以分为加密的和不加密的；usbwallet支持ledger和trenzer两种硬件钱包。
# keystore：本地文件夹
keystore类型的钱包其实是一个本地文件夹目录。在这个目录下可以存放多个文件，每个文件都存储着一个私钥信息。这些文件都是json格式，其中的私钥可以是加密的，也可以是非加密的明文。但非加密的格式已经被废弃了（谁都不想把自己的私钥明文存放在某个文件里）。 keystore的目录路径可以在配置文件中指定，默认路径是<DataDir>/keystore。每一个文件的文件名格式为：UTC--<created_at UTC ISO8601>--<address hex>。例如UTC--2016-03-22T12-57-55-- 7ef5a6135f1fd6a02593eedc869c6d41d934aef8。 keystore目录和目录内的文件是可以直接拷贝的。也就是说，如果你想把某个私钥转移到别的电脑上，你可以直接拷贝文件到其它电脑的keystore目录。拷贝整个keystore目录也是一样的。

# HD：分层确定性（Hierarchical Deterministic）钱包
我们首先解释一下HD（Hierarchical Deterministic）的概念。这个概念的中文名称叫做“分层确定性”，我的理解是这是一种key的派生方式，它可以在只使用一个公钥（我们称这个公钥为主公钥，其对应的私钥称为主私钥）的情况下，生成任意多个子公钥，而这些子公钥都是可以被主私钥控制的。HD的概念最早是从比特币的BIP-32提案中提出来的。每一个key都有自己的路径，即是是一个派生的key，这一点和keystore类型是一样的。我们先来看一下HD账户的路径格式：
                         m / purpose’ / coin_type’ / account’ / change / address_index
这种路径规范不是一下子形成的。虽然BIP-32提出了HD的概念，但实现者自由度比较大，导致相互之间兼容性很差。因此在BIP-43中增加了purpose字段；而在BIP-44中对路径规范进行了大量的扩展，使其可以用在不同币种上。在BIP-43中推荐purpose的值为44’(0x8000002C)；而在BIPSLIP-44中为以太坊类型的coin_type为配的值为60’(0x8000003c)。所以我们在以太坊中可能看到形如m/44'/60'/0'/0这样的路径。在accounts模块中共支持两种HD钱包：Ledger和Trenzer。它们都是非常有名的硬件钱包，有兴趣的朋友可以自己搜索一下，这是不作过多介绍。

# 目录结构
accounts模块下的源文件比较多，这里不一一说明，只挑一些比较重要的聊一下。
### accounts.go
accounts.go定义了accounts模块对外导出的一些结构体和接口，包括Account结构体、Wallet接口和Backend接口。其中Account由一个以太坊地址和钱包路径组成；而各种类型的钱包需要实现Wallet和Backend接口来接入账入管理。
### hd.go
hd.go中定义了HD类型的钱包的路径解析等函数。这个文件中的注释还解析了HD路径一些知识，值得一看。（但我认为它关于哪个BIP提案提出的哪个规范说得不对，比如注释中提到BIP-32定义了路径规范m / purpose' / coin_type' / account' / change / address_index，这应该是错误的，我们前面提到过，purpose是在BIP-43中提出的，而整个路径规范是在BIP-44中提出的）
### manager.go
manager.go中定义了Manager结构及其方法。这是accounts模块对外导出的主要的结构和方法之一。其它模块（比如cmd/geth中）通过这个结构体提供的方法对钱包进行管理。
### url.go
这个文件中的代码定义了代表以太坊钱包路径的URL结构体及相关函数。与hd.go中不同的是，URL结构体中保存了钱包的类型（scheme）和钱包路径的字符串形式的表示；而hd.go中定义了HD钱包路径的类型（非字符串类型）的解析及字符串转换等方法。</br>
## keystore
这是一个子目录，此目录下的代码实现了keystore类型的钱包。
### account_cache.go
此文件中的代码实现了accountCache结构体及方法。accountCache的功能是在内存中缓存keystore钱包目录下所有账号信息。无论keystore目录中的文件无何变动（新建、删除、修改），accountCache都可以在扫描目录时将变动更新到内存中。
### file_cache.go
此文件中的代码实现了fileCache结构体及相关代码。与account_cache.go类似，file_cache.go中实现了对keystore目录下所有文件的信息的缓存。accountCache就是通过fileCache来获取文件变动的信息，进而得到账号变动信息的。
### key.go
key.go主要定义了Key结构体及其json格式的marshal/unmarshal方式。另外这个文件中还定义了通过keyStore接口将Key写入文件中的函数。keyStore接口中定义了Key被写入文件的具体细节，在passphrase.go和plain.go中都有实现。
### keystore.go
这个文件里的代码定义了KeyStore结构体及其方法。KeyStore结构体实现了Backend接口，是keystore类型的钱包的后端实现。同时它也实现了keystore类型钱包的大多数功能。
### passphrase.go
passphrase.go中定义了keyStorePassphrase结构体及其方法。keyStorePassphrase结构体是对keyStore接口（在key.go文件中）的一种实现方式，它会要求调用者提供一个密码，从而使用aes加密算法加密私钥后，将加密数据写入文件中。
### plain.go
这个文件中的代码定义了keyStorePlain结构体及其方法。keyStorePlain与keyStorePassphrase类似，也是对keyStore接口的实现。不同的是，keyStorePlain直接将密码明文存储在文件中。目前这种方式已被标记弃用且整个以太坊项目中都没有调用这个文件里的函数的地方，确实谁也不想将自己的私钥明文存在本地磁盘上。
### wallet.go
wallet.go中定义了keystoreWallet结构体及其方法。keystoreWallet是keystore类型的钱包的实现，但其功能基本都是调用KeyStore对象实现的。
### watch.go
watch.go中定义了watcher结构体及其方法。watcher用来监控keystore目录下的文件，如果文件发生变化，则立即调用account_cache.go中的代码重新扫描账户信息。但watcher只在某些系统下有效，这是文件的build注释：// +build darwin,!ios freebsd linux,!arm64 netbsd solaris</br>
## usbwallet
这是一个子目录，此目录下的代码实现了对通过usb接入的硬件钱包的访问，但只支持ledger和trezor两种类型的硬件钱包。
### hub.go
hub.go中定义了Hub结构体及其方法。Hub结构体实现了Backend接口，是usbwallet类型的钱包的后端实现。
### ledger.go
ledger.go中定义了ledgerDriver结构体及其方法。ledgerDriver结构体是driver接口的实现，它实现了与ledger类型的硬件钱包通信协议和代码。
### trezor.go
trezor.go中定义了trezorDriver结构体及其方法。与ledgerDriver类似，trezorDriver结构体也是driver接口的实现，它实现了与trezor类型的硬件钱包的通信协议和代码。
### wallet.go
wallet.go中定义了wallet结构体。wallet结构体实现了Wallet接口，是硬件钱包的具体实现。但它内部其实主要调用硬件钱包的driver实现相关功能。
## scwallet
这个文件夹是关于不同account之间的互相安全通信（secure wallet），通过定义会话秘钥、二级秘钥来确保通话双方的信息真实、不被篡改、利用。 尤其是转账信息更不能被利用、被他人打开、和被篡改。
## backend
此文件夹是为了和外部的其他账户进行通信
## abi
ABI是Application Binary Interface的缩写，字面意思 应用二进制接口，可以通俗的理解为合约的接口说明。当合约被编译后，那么它的abi也就确定了。abi主要是处理智能合约与账户的交互。
</br>

账号是通过数据结构和接口来定义了
# 数据结构
账号

	// Account represents an Ethereum account located at a specific location defined
	// by the optional URL field.
	// 一个账号是20个字节的数据。 URL是可选的字段。
	type Account struct {
		Address common.Address `json:"address"` // Ethereum account address derived from the key
		URL     URL            `json:"url"`     // Optional resource locator within a backend
	}

	const (
		HashLength    = 32
		AddressLength = 20
	)
	// Address represents the 20 byte address of an Ethereum account.
	type Address [AddressLength]byte


钱包。钱包应该是这里面最重要的一个接口了。 具体的钱包也是实现了这个接口。
钱包又有所谓的分层确定性钱包和普通钱包。

	// Wallet represents a software or hardware wallet that might contain one or more
	// accounts (derived from the same seed).
	// Wallet 是指包含了一个或多个账户的软件钱包或者硬件钱包
	type Wallet interface {
		// URL retrieves the canonical path under which this wallet is reachable. It is
		// user by upper layers to define a sorting order over all wallets from multiple
		// backends.
		// URL 用来获取这个钱包可以访问的规范路径。 它会被上层使用用来从所有的后端的钱包来排序。
		URL() URL
	
		// Status returns a textual status to aid the user in the current state of the
		// wallet. It also returns an error indicating any failure the wallet might have
		// encountered.
		// 用来返回一个文本值用来标识当前钱包的状态。 同时也会返回一个error用来标识钱包遇到的任何错误。
		Status() (string, error)
	
		// Open initializes access to a wallet instance. It is not meant to unlock or
		// decrypt account keys, rather simply to establish a connection to hardware
		// wallets and/or to access derivation seeds.
		// Open 初始化对钱包实例的访问。这个方法并不意味着解锁或者解密账户，而是简单地建立与硬件钱包的连接和/或访问衍生种子。
		// The passphrase parameter may or may not be used by the implementation of a
		// particular wallet instance. The reason there is no passwordless open method
		// is to strive towards a uniform wallet handling, oblivious to the different
		// backend providers.
		// passphrase参数可能在某些实现中并不需要。 没有提供一个无passphrase参数的Open方法的原因是为了提供一个统一的接口。 
		// Please note, if you open a wallet, you must close it to release any allocated
		// resources (especially important when working with hardware wallets).
		// 请注意，如果你open了一个钱包，你必须close它。不然有些资源可能没有释放。 特别是使用硬件钱包的时候需要特别注意。
		Open(passphrase string) error
	
		// Close releases any resources held by an open wallet instance.
		// Close 释放由Open方法占用的任何资源。
		Close() error
	
		// Accounts retrieves the list of signing accounts the wallet is currently aware
		// of. For hierarchical deterministic wallets, the list will not be exhaustive,
		// rather only contain the accounts explicitly pinned during account derivation.
		// Accounts用来获取钱包发现了账户列表。 对于分层次的钱包， 这个列表不会详尽的列出所有的账号， 而是只包含在帐户派生期间明确固定的帐户。
		Accounts() []Account
	
		// Contains returns whether an account is part of this particular wallet or not.
		// Contains 返回一个账号是否属于本钱包。
		Contains(account Account) bool
	
		// Derive attempts to explicitly derive a hierarchical deterministic account at
		// the specified derivation path. If requested, the derived account will be added
		// to the wallet's tracked account list.
		// Derive尝试在指定的派生路径上显式派生出分层确定性帐户。 如果pin为true，派生帐户将被添加到钱包的跟踪帐户列表中。
		Derive(path DerivationPath, pin bool) (Account, error)
	
		// SelfDerive sets a base account derivation path from which the wallet attempts
		// to discover non zero accounts and automatically add them to list of tracked
		// accounts.
		// SelfDerive设置一个基本帐户导出路径，从中钱包尝试发现非零帐户，并自动将其添加到跟踪帐户列表中。
		// Note, self derivaton will increment the last component of the specified path
		// opposed to decending into a child path to allow discovering accounts starting
		// from non zero components.
		// 注意，SelfDerive将递增指定路径的最后一个组件，而不是下降到子路径，以允许从非零组件开始发现帐户。
		// You can disable automatic account discovery by calling SelfDerive with a nil
		// chain state reader.
		// 你可以通过传递一个nil的ChainStateReader来禁用自动账号发现。
		SelfDerive(base DerivationPath, chain ethereum.ChainStateReader)
	
		// SignHash requests the wallet to sign the given hash.
		// SignHash 请求钱包来给传入的hash进行签名。
		// It looks up the account specified either solely via its address contained within,
		// or optionally with the aid of any location metadata from the embedded URL field.
		//它可以通过其中包含的地址（或可选地借助嵌入式URL字段中的任何位置元数据）来查找指定的帐户。
		// If the wallet requires additional authentication to sign the request (e.g.
		// a password to decrypt the account, or a PIN code o verify the transaction),
		// an AuthNeededError instance will be returned, containing infos for the user
		// about which fields or actions are needed. The user may retry by providing
		// the needed details via SignHashWithPassphrase, or by other means (e.g. unlock
		// the account in a keystore).
		// 如果钱包需要额外的验证才能签名(比如说 需要密码来解锁账号， 或者是需要一个PIN 代码来验证交易。)
		// 会返回一个AuthNeededError的错误，里面包含了用户的信息，以及哪些字段或者操作需要提供。
		// 用户可以通过 SignHashWithPassphrase来签名或者通过其他手段(在keystore里面解锁账号)
		SignHash(account Account, hash []byte) ([]byte, error)
	
		// SignTx requests the wallet to sign the given transaction.
		// SignTx 请求钱包对指定的交易进行签名。
		// It looks up the account specified either solely via its address contained within,
		// or optionally with the aid of any location metadata from the embedded URL field.
		// 
		// If the wallet requires additional authentication to sign the request (e.g.
		// a password to decrypt the account, or a PIN code o verify the transaction),
		// an AuthNeededError instance will be returned, containing infos for the user
		// about which fields or actions are needed. The user may retry by providing
		// the needed details via SignTxWithPassphrase, or by other means (e.g. unlock
		// the account in a keystore).
		SignTx(account Account, tx *types.Transaction, chainID *big.Int) (*types.Transaction, error)
	
		// SignHashWithPassphrase requests the wallet to sign the given hash with the
		// given passphrase as extra authentication information.
		// SignHashWithPassphrase请求钱包使用给定的passphrase来签名给定的hash
		// It looks up the account specified either solely via its address contained within,
		// or optionally with the aid of any location metadata from the embedded URL field.
		SignHashWithPassphrase(account Account, passphrase string, hash []byte) ([]byte, error)
	
		// SignTxWithPassphrase requests the wallet to sign the given transaction, with the
		// given passphrase as extra authentication information.
		// SignHashWithPassphrase请求钱包使用给定的passphrase来签名给定的transaction
		// It looks up the account specified either solely via its address contained within,
		// or optionally with the aid of any location metadata from the embedded URL field.
		SignTxWithPassphrase(account Account, passphrase string, tx *types.Transaction, chainID *big.Int) (*types.Transaction, error)
	}


后端 Backend
	
	// Backend is a "wallet provider" that may contain a batch of accounts they can
	// sign transactions with and upon request, do so.
	// Backend是一个钱包提供器。 可以包含一批账号。他们可以根据请求签署交易，这样做。
	type Backend interface {
		// Wallets retrieves the list of wallets the backend is currently aware of.
		// Wallets获取当前能够查找到的钱包
		// The returned wallets are not opened by default. For software HD wallets this
		// means that no base seeds are decrypted, and for hardware wallets that no actual
		// connection is established.
		// 返回的钱包默认是没有打开的。 
		// The resulting wallet list will be sorted alphabetically based on its internal
		// URL assigned by the backend. Since wallets (especially hardware) may come and
		// go, the same wallet might appear at a different positions in the list during
		// subsequent retrievals.
		//所产生的钱包列表将根据后端分配的内部URL按字母顺序排序。 由于钱包（特别是硬件钱包）可能会打开和关闭，所以在随后的检索过程中，相同的钱包可能会出现在列表中的不同位置。
		Wallets() []Wallet
	
		// Subscribe creates an async subscription to receive notifications when the
		// backend detects the arrival or departure of a wallet.
		// 订阅创建异步订阅，以便在后端检测到钱包的到达或离开时接收通知。
		Subscribe(sink chan<- WalletEvent) event.Subscription
	}


## manager.go
Manager是一个包含所有东西的账户管理工具。 可以和所有的Backends来通信来签署交易。

数据结构

	// Manager is an overarching account manager that can communicate with various
	// backends for signing transactions.
	type Manager struct {
		// 所有已经注册的Backend
		backends map[reflect.Type][]Backend // Index of backends currently registered
		// 所有Backend的更新订阅器
		updaters []event.Subscription       // Wallet update subscriptions for all backends
		// backend更新的订阅槽
		updates  chan WalletEvent           // Subscription sink for backend wallet changes
		// 所有已经注册的Backends的钱包的缓存
		wallets  []Wallet                   // Cache of all wallets from all registered backends
		// 钱包到达和离开的通知
		feed event.Feed // Wallet feed notifying of arrivals/departures
		// 退出队列
		quit chan chan error
		lock sync.RWMutex
	}


创建Manager

	
	// NewManager creates a generic account manager to sign transaction via various
	// supported backends.
	func NewManager(backends ...Backend) *Manager {
		// Subscribe to wallet notifications from all backends
		updates := make(chan WalletEvent, 4*len(backends))
	
		subs := make([]event.Subscription, len(backends))
		for i, backend := range backends {
			subs[i] = backend.Subscribe(updates)
		}
		// Retrieve the initial list of wallets from the backends and sort by URL
		var wallets []Wallet
		for _, backend := range backends {
			wallets = merge(wallets, backend.Wallets()...)
		}
		// Assemble the account manager and return
		am := &Manager{
			backends: make(map[reflect.Type][]Backend),
			updaters: subs,
			updates:  updates,
			wallets:  wallets,
			quit:     make(chan chan error),
		}
		for _, backend := range backends {
			kind := reflect.TypeOf(backend)
			am.backends[kind] = append(am.backends[kind], backend)
		}
		go am.update()
	
		return am
	}

update方法。 是一个goroutine。会监听所有backend触发的更新信息。 然后转发给feed.

	// update is the wallet event loop listening for notifications from the backends
	// and updating the cache of wallets.
	func (am *Manager) update() {
		// Close all subscriptions when the manager terminates
		defer func() {
			am.lock.Lock()
			for _, sub := range am.updaters {
				sub.Unsubscribe()
			}
			am.updaters = nil
			am.lock.Unlock()
		}()
	
		// Loop until termination
		for {
			select {
			case event := <-am.updates:
				// Wallet event arrived, update local cache
				am.lock.Lock()
				switch event.Kind {
				case WalletArrived:
					am.wallets = merge(am.wallets, event.Wallet)
				case WalletDropped:
					am.wallets = drop(am.wallets, event.Wallet)
				}
				am.lock.Unlock()
	
				// Notify any listeners of the event
				am.feed.Send(event)
	
			case errc := <-am.quit:
				// Manager terminating, return
				errc <- nil
				return
			}
		}
	}

返回backend

	// Backends retrieves the backend(s) with the given type from the account manager.
	func (am *Manager) Backends(kind reflect.Type) []Backend {
		return am.backends[kind]
	}


订阅消息

	// Subscribe creates an async subscription to receive notifications when the
	// manager detects the arrival or departure of a wallet from any of its backends.
	func (am *Manager) Subscribe(sink chan<- WalletEvent) event.Subscription {
		return am.feed.Subscribe(sink)
	}


对于node来说。是什么时候创建的账号管理器。

	// New creates a new P2P node, ready for protocol registration.
	func New(conf *Config) (*Node, error) {
		...
		am, ephemeralKeystore, err := makeAccountManager(conf)
		


	
	func makeAccountManager(conf *Config) (*accounts.Manager, string, error) {
		scryptN := keystore.StandardScryptN
		scryptP := keystore.StandardScryptP
		if conf.UseLightweightKDF {
			scryptN = keystore.LightScryptN
			scryptP = keystore.LightScryptP
		}
	
		var (
			keydir    string
			ephemeral string
			err       error
		)
		switch {
		case filepath.IsAbs(conf.KeyStoreDir):
			keydir = conf.KeyStoreDir
		case conf.DataDir != "":
			if conf.KeyStoreDir == "" {
				keydir = filepath.Join(conf.DataDir, datadirDefaultKeyStore)
			} else {
				keydir, err = filepath.Abs(conf.KeyStoreDir)
			}
		case conf.KeyStoreDir != "":
			keydir, err = filepath.Abs(conf.KeyStoreDir)
		default:
			// There is no datadir.
			keydir, err = ioutil.TempDir("", "go-ethereum-keystore")
			ephemeral = keydir
		}
		if err != nil {
			return nil, "", err
		}
		if err := os.MkdirAll(keydir, 0700); err != nil {
			return nil, "", err
		}
		// Assemble the account manager and supported backends
		// 创建了一个KeyStore的backend
		backends := []accounts.Backend{
			keystore.NewKeyStore(keydir, scryptN, scryptP),
		}
		// 如果是USB钱包。 需要做一些额外的操作。
		if !conf.NoUSB {
			// Start a USB hub for Ledger hardware wallets
			if ledgerhub, err := usbwallet.NewLedgerHub(); err != nil {
				log.Warn(fmt.Sprintf("Failed to start Ledger hub, disabling: %v", err))
			} else {
				backends = append(backends, ledgerhub)
			}
			// Start a USB hub for Trezor hardware wallets
			if trezorhub, err := usbwallet.NewTrezorHub(); err != nil {
				log.Warn(fmt.Sprintf("Failed to start Trezor hub, disabling: %v", err))
			} else {
				backends = append(backends, trezorhub)
			}
		}
		return accounts.NewManager(backends...), ephemeral, nil
	}
