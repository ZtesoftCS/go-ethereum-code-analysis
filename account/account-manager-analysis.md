##数据结构分析
以太坊的账户管理定义在accounts/manager.go中，其数据结构为：
```
// Manager is an overarching account manager that can communicate with various
// backends for signing transactions.
    type Manager struct {
        backends map[reflect.Type][]Backend // Index of backends currently registered
        updaters []event.Subscription       // Wallet update subscriptions for all backends
        updates  chan WalletEvent           // Subscription sink for backend wallet changes
        wallets  []Wallet                   // Cache of all wallets from all registered backends
    
        feed event.Feed // Wallet feed notifying of arrivals/departures
    
        quit chan chan error
        lock sync.RWMutex
    }
```
backends是所有已注册的Backend<br>
updaters是所有的Backend的更新订阅器<br>
updates是Backend更新的订阅槽<br>
wallets是所有已经注册的Backends的钱包的缓存<br>
feed是钱包到达和离开的通知<br>
quit是退出队列的通道<br>
这里主要来看一下Backend的定义。Backend是一个钱包的提供器，包含一系列的账号。Backend可以请求签名交易。<br>
```
// Backend is a "wallet provider" that may contain a batch of accounts they can
// sign transactions with and upon request, do so.
    type Backend interface {
        // Wallets retrieves the list of wallets the backend is currently aware of.
        //
        // The returned wallets are not opened by default. For software HD wallets this
        // means that no base seeds are decrypted, and for hardware wallets that no actual
        // connection is established.
        //
        // The resulting wallet list will be sorted alphabetically based on its internal
        // URL assigned by the backend. Since wallets (especially hardware) may come and
        // go, the same wallet might appear at a different positions in the list during
        // subsequent retrievals.
        Wallets() []Wallet
    
        // Subscribe creates an async subscription to receive notifications when the
        // backend detects the arrival or departure of a wallet.
        Subscribe(sink chan<- WalletEvent) event.Subscription
    }
```
Backend是一个接口。其中，Wallets()返回当前可用的钱包，按字母顺序排序。<br>
Subscribe()是创建异步订阅的方法，当钱包发生变动时会通过通道接收到消息并执行。<br>
##启动时账户管理加载
在使用geth命令启动中，代码会调用makeFullNode方法产生一个节点。在这个方法中，会调用一个makeConfigNode方法。<br>
在这个方法中，代码会将我们输入的启动命令进行解析，并放置在gethConfig中。接下来会调用node.New方法创建一个节点。<br>
在node.New方法中，有一个makeAccountManager方法，这个方法是用来建立账户管理系统的。<br>
```
    func makeAccountManager(conf *Config) (*accounts.Manager, string, error) {
        scryptN, scryptP, keydir, err := conf.AccountConfig()
        var ephemeral string
        if keydir == "" {
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
        backends := []accounts.Backend{
            keystore.NewKeyStore(keydir, scryptN, scryptP),
        }
    ...
```
在这个方法中，conf.AccountConfig方法会先将我们输入的参数进行解析，并获取keystore的初始值。接下来通过keystore.NewKeyStore方法创建一个Backend。<br>
```
    func NewKeyStore(keydir string, scryptN, scryptP int) *KeyStore {
        keydir, _ = filepath.Abs(keydir)
        ks := &KeyStore{storage: &keyStorePassphrase{keydir, scryptN, scryptP}}
        ks.init(keydir)
        return ks
    }
```
在这个方法中，keystore会通过init方法进行初始化。<br>
```
    func (ks *KeyStore) init(keydir string) {
        // Lock the mutex since the account cache might call back with events
        ks.mu.Lock()
        defer ks.mu.Unlock()
    
        // Initialize the set of unlocked keys and the account cache
        ks.unlocked = make(map[common.Address]*unlocked)
        ks.cache, ks.changes = newAccountCache(keydir)
    
        // TODO: In order for this finalizer to work, there must be no references
        // to ks. addressCache doesn't keep a reference but unlocked keys do,
        // so the finalizer will not trigger until all timed unlocks have expired.
        runtime.SetFinalizer(ks, func(m *KeyStore) {
            m.cache.close()
        })
        // Create the initial list of wallets from the cache
        accs := ks.cache.accounts()
        ks.wallets = make([]accounts.Wallet, len(accs))
        for i := 0; i < len(accs); i++ {
            ks.wallets[i] = &keystoreWallet{account: accs[i], keystore: ks}
        }
    }
```
这里，首先会通过newAccountCache方法将文件的路径写入到keystore的缓存中，并在ks.changes通道中写入数据。<br>
然后会通过缓存中的accounts()方法从文件中将账户信息写入到缓存中。<br>
在accounts中，一步步跟进去，会找到scanAccounts方法。这个方法会计算create，delete，和update的账户信息，并通过readAccount方法将账户信息写入到缓存中。<br>
至此，项目管理的keystore和backend已经创建好，并将账户信息写入到内存中。<br>
接下来，会通过accounts.NewManager创建一个account manager对账户进行管理。