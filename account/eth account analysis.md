## 1.personal.newAccount创建账户方法
用户在控制台输入personal.newAccount会创建一个新的账户，会进入到ethapi.api中的newAccount方法中，这个方法会返回一个地址。
```
 func (s *PrivateAccountAPI) NewAccount(password string) (common.Address, error) {
    acc, err := fetchKeystore(s.am).NewAccount(password)
    if err == nil {
      return acc.Address, nil
    }
    return common.Address{}, err
  }
```
 
  
创建账户过程中，首先会通过账户管理系统（account manager）来获取Keystore，然后通过椭圆加密算法产生公私钥对，并获取地址
  
  ```
  func newKey(rand io.Reader) (*Key, error) {
    privateKeyECDSA, err := ecdsa.GenerateKey(crypto.S256(), rand)
    if err != nil {
      return nil, err
    }
    return newKeyFromECDSA(privateKeyECDSA), nil
  }
  ```
  
在获取到公私钥对后，会对用户输入的密码进行加密，并保存入文件。
```

  func (ks keyStorePassphrase) StoreKey(filename string, key *Key, auth string) error {
    keyjson, err := EncryptKey(key, auth, ks.scryptN, ks.scryptP)
    if err != nil {
      return err
    }
    return writeKeyFile(filename, keyjson)
  }
  ```
  
在保存文件的同时，会将新创建的账户加入到缓存中。
```

  func (ks *KeyStore) NewAccount(passphrase string) (accounts.Account, error) {
    _, account, err := storeNewKey(ks.storage, crand.Reader, passphrase)
    if err != nil {
      return accounts.Account{}, err
    }
    // Add the account to the cache immediately rather
    // than waiting for file system notifications to pick it up.
    ks.cache.add(account)
    ks.refreshWallets()
    return account, nil
  }
  ```
  
  ## 2.personal.listAccounts列出所有账户方法
  
用户在控制台输入personal.listAccounts，会进入到ethapi.api中的listAccounts方法中，这个方法会从用户管理中读取所有钱包信息，返回所有注册钱包下的所有地址信息。
```
 func (s *PrivateAccountAPI) ListAccounts() []common.Address {
  addresses := make([]common.Address, 0) // return [] instead of nil if empty
  for _, wallet := range s.am.Wallets() {
   for _, account := range wallet.Accounts() {
    addresses = append(addresses, account.Address)
   }
  }
  return addresses
 }
 ```
 ## 3.eth.sendTransaction 

 sendTransaction经过RPC调用之后，最终会调用ethapi.api.go中的sendTransaction方法。
 ```
     // SendTransaction will create a transaction from the given arguments and
     // tries to sign it with the key associated with args.To. If the given passwd isn't
     // able to decrypt the key it fails.
     func (s *PrivateAccountAPI) SendTransaction(ctx context.Context, args SendTxArgs, passwd string) (common.Hash, error) {
        // Look up the wallet containing the requested signer
        account := accounts.Account{Address: args.From}

        wallet, err := s.am.Find(account)
        if err != nil {
            return common.Hash{}, err
        }

        //对于每一个账户，Nonce会随着转账数的增加而增加，这个参数主要是为了防止双花攻击。
        if args.Nonce == nil {
            // Hold the addresse's mutex around signing to prevent concurrent assignment of
            // the same nonce to multiple accounts.
            s.nonceLock.LockAddr(args.From)
            defer s.nonceLock.UnlockAddr(args.From)
        }

        // Set some sanity defaults and terminate on failure
        if err := args.setDefaults(ctx, s.b); err != nil {
            return common.Hash{}, err
        }
        // Assemble the transaction and sign with the wallet
        tx := args.toTransaction()
        ...
```
 这个方法利用传入的参数from构造一个account，表示转出方。接着会通过账户管理系统accountManager获得该账户的钱包（wallet）。<br>
 am.Find方法会从账户管理系统中对钱包进行遍历，找到包含这个account的钱包。
 ```
     // Find attempts to locate the wallet corresponding to a specific account. Since
     // accounts can be dynamically added to and removed from wallets, this method has
     // a linear runtime in the number of wallets.
     func (am *Manager) Find(account Account) (Wallet, error) {
        am.lock.RLock()
        defer am.lock.RUnlock()

        for _, wallet := range am.wallets {
            if wallet.Contains(account) {
                return wallet, nil
            }
        }
        return nil, ErrUnknownAccount
     }
 ```
 接下来会调用setDefaults方法设置一些交易的默认值。如果没有设置Gas，GasPrice，Nonce等，那么它们将会被设置为默认值。<br>
 当交易的这些参数都设置好之后，会利用toTransaction方法创建一笔交易。
 ```
     func (args *SendTxArgs) toTransaction() *types.Transaction {
        var input []byte
        if args.Data != nil {
            input = *args.Data
        } else if args.Input != nil {
            input = *args.Input
        }
        if args.To == nil {
            return types.NewContractCreation(uint64(*args.Nonce), (*big.Int)(args.Value), uint64(*args.Gas), (*big.Int)(args.GasPrice), input)
        }
        return types.NewTransaction(uint64(*args.Nonce), *args.To, (*big.Int)(args.Value), uint64(*args.Gas), (*big.Int)(args.GasPrice), input)
     }
 ```
这里会对传入的交易信息的to参数进行判断。如果没有to值，那么这是一笔合约转账；而如果有to值，那么就是发起的一笔转账。最终，代码会调用NewTransaction创建一笔交易信息。
```
    func newTransaction(nonce uint64, to *common.Address, amount *big.Int, gasLimit uint64, gasPrice *big.Int, data []byte) *Transaction {
        if len(data) > 0 {
            data = common.CopyBytes(data)
        }
        d := txdata{
            AccountNonce: nonce,
            Recipient:    to,
            Payload:      data,
            Amount:       new(big.Int),
            GasLimit:     gasLimit,
            Price:        new(big.Int),
            V:            new(big.Int),
            R:            new(big.Int),
            S:            new(big.Int),
        }
        if amount != nil {
            d.Amount.Set(amount)
        }
        if gasPrice != nil {
            d.Price.Set(gasPrice)
        }

        return &Transaction{data: d}
    }
```
这里就是填充了交易结构体中的一些参数，来创建一个交易。到这里，我们的交易就已经创建成功了。<br>
回到sendTransaction方法中，此时我们已经创建好了一笔交易，接着我们获取区块链的配置信息，检查是否是EIP155的配置，并获取链ID。
```
    ...
            var chainID *big.Int
            	if config := s.b.ChainConfig(); config.IsEIP155(s.b.CurrentBlock().Number()) {
            		chainID = config.ChainId
            	}
            	signed, err := wallet.SignTx(account, tx, chainID)
            	if err != nil {
            		return common.Hash{}, err
            	}
            	return submitTransaction(ctx, s.b, signed)
            }
```
接下来就要对这笔交易签名来确保这笔交易的真实有效。这里调用SignTx实现签名。
```
// SignTx signs the given transaction with the requested account.
    func (ks *KeyStore) SignTx(a accounts.Account, tx *types.Transaction, chainID *big.Int) (*types.Transaction, error) {
        // Look up the key to sign with and abort if it cannot be found
        ks.mu.RLock()
        defer ks.mu.RUnlock()
    
        unlockedKey, found := ks.unlocked[a.Address]
        if !found {
            return nil, ErrLocked
        }
        // Depending on the presence of the chain ID, sign with EIP155 or homestead
        if chainID != nil {
            return types.SignTx(tx, types.NewEIP155Signer(chainID), unlockedKey.PrivateKey)
        }
        return types.SignTx(tx, types.HomesteadSigner{}, unlockedKey.PrivateKey)
    }
```
这里首先我们先验证账户是否已解锁。若没有解锁，则直接则异常退出。接下来我们检查chainID，判断是使用哪一种签名的方式,调用SignTx方法进行签名。
```
    // SignTx signs the transaction using the given signer and private key
    func SignTx(tx *Transaction, s Signer, prv *ecdsa.PrivateKey) (*Transaction, error) {
        h := s.Hash(tx)
        sig, err := crypto.Sign(h[:], prv)
        if err != nil {
            return nil, err
        }
        return tx.WithSignature(s, sig)
    }
```
在签名时，首先获取交易的RLP哈希值，然后用传入的私钥进行椭圆加密。接着调用WithSignature方法进行初始化。<br>
进行到这里，我们交易的签名已经完成，并且封装成为一个带签名的交易。<br>
然后，我们就需要将这笔交易提交出去。调用SubmitTransaction方法提交交易。
```
// submitTransaction is a helper function that submits tx to txPool and logs a message.
    func submitTransaction(ctx context.Context, b Backend, tx *types.Transaction) (common.Hash, error) {
        if err := b.SendTx(ctx, tx); err != nil {
            return common.Hash{}, err
        }
        if tx.To() == nil {
            signer := types.MakeSigner(b.ChainConfig(), b.CurrentBlock().Number())
            from, err := types.Sender(signer, tx)
            if err != nil {
                return common.Hash{}, err
            }
            addr := crypto.CreateAddress(from, tx.Nonce())
            log.Info("Submitted contract creation", "fullhash", tx.Hash().Hex(), "contract", addr.Hex())
        } else {
            log.Info("Submitted transaction", "fullhash", tx.Hash().Hex(), "recipient", tx.To())
        }
        return tx.Hash(), nil
    }
```
submitTransaction方法会将交易发送给backend进行处理，返回经过签名后的交易的hash值。这里主要是SendTx方法对交易进行处理。<br>
sendTx方法会将参数转给txpool的Addlocal方法进行处理，而AddLocal方法会将该笔交易放入到交易池中进行等待。这里我们看将交易放入到交易池中的方法。
```
    // addTx enqueues a single transaction into the pool if it is valid.
    func (pool *TxPool) addTx(tx *types.Transaction, local bool) error {
        pool.mu.Lock()
        defer pool.mu.Unlock()
    
        // Try to inject the transaction and update any state
        replace, err := pool.add(tx, local)
        if err != nil {
            return err
        }
        // If we added a new transaction, run promotion checks and return
        if !replace {
            from, _ := types.Sender(pool.signer, tx) // already validated
            pool.promoteExecutables([]common.Address{from})
        }
        return nil
    }
```
这里一共有两部操作，第一步操作是调用add方法将交易放入到交易池中，第二步是判断replace参数。如果该笔交易合法并且交易原来不存在在交易池中，则执行promoteExecutables方法，将可处理的交易变为待处理（pending）。<br>
首先看第一步add方法。
```
// add validates a transaction and inserts it into the non-executable queue for
// later pending promotion and execution. If the transaction is a replacement for
// an already pending or queued one, it overwrites the previous and returns this
// so outer code doesn't uselessly call promote.
//
// If a newly added transaction is marked as local, its sending account will be
// whitelisted, preventing any associated transaction from being dropped out of
// the pool due to pricing constraints.
    func (pool *TxPool) add(tx *types.Transaction, local bool) (bool, error) {
        // If the transaction is already known, discard it
        hash := tx.Hash()
        if pool.all[hash] != nil {
            log.Trace("Discarding already known transaction", "hash", hash)
            return false, fmt.Errorf("known transaction: %x", hash)
        }
        // If the transaction fails basic validation, discard it
        if err := pool.validateTx(tx, local); err != nil {
            log.Trace("Discarding invalid transaction", "hash", hash, "err", err)
            invalidTxCounter.Inc(1)
            return false, err
        }
        // If the transaction pool is full, discard underpriced transactions
        if uint64(len(pool.all)) >= pool.config.GlobalSlots+pool.config.GlobalQueue {
            // If the new transaction is underpriced, don't accept it
            if pool.priced.Underpriced(tx, pool.locals) {
                log.Trace("Discarding underpriced transaction", "hash", hash, "price", tx.GasPrice())
                underpricedTxCounter.Inc(1)
                return false, ErrUnderpriced
            }
            // New transaction is better than our worse ones, make room for it
            drop := pool.priced.Discard(len(pool.all)-int(pool.config.GlobalSlots+pool.config.GlobalQueue-1), pool.locals)
            for _, tx := range drop {
                log.Trace("Discarding freshly underpriced transaction", "hash", tx.Hash(), "price", tx.GasPrice())
                underpricedTxCounter.Inc(1)
                pool.removeTx(tx.Hash())
            }
        }
        // If the transaction is replacing an already pending one, do directly
        from, _ := types.Sender(pool.signer, tx) // already validated
        if list := pool.pending[from]; list != nil && list.Overlaps(tx) {
            // Nonce already pending, check if required price bump is met
            inserted, old := list.Add(tx, pool.config.PriceBump)
            if !inserted {
                pendingDiscardCounter.Inc(1)
                return false, ErrReplaceUnderpriced
            }
            // New transaction is better, replace old one
            if old != nil {
                delete(pool.all, old.Hash())
                pool.priced.Removed()
                pendingReplaceCounter.Inc(1)
            }
            pool.all[tx.Hash()] = tx
            pool.priced.Put(tx)
            pool.journalTx(from, tx)
    
            log.Trace("Pooled new executable transaction", "hash", hash, "from", from, "to", tx.To())
    
            // We've directly injected a replacement transaction, notify subsystems
            go pool.txFeed.Send(TxPreEvent{tx})
    
            return old != nil, nil
        }
        // New transaction isn't replacing a pending one, push into queue
        replace, err := pool.enqueueTx(hash, tx)
        if err != nil {
            return false, err
        }
        // Mark local addresses and journal local transactions
        if local {
            pool.locals.add(from)
        }
        pool.journalTx(from, tx)
    
        log.Trace("Pooled new future transaction", "hash", hash, "from", from, "to", tx.To())
        return replace, nil
    }
```
这个方法主要执行以下操作：<br>
    1.检查交易池是否含有这笔交易，如果有这笔交易，则异常退出。<br>
    2.调用validateTx方法对交易的合法性进行验证。如果是非法的交易，则异常退出。<br>
    3.接下来判断交易池是否超过容量。<br>
        <1>如果超过容量，并且该笔交易的费用低于当前交易池中列表的最小值，则拒绝这一笔交易。<br>
        <2>如果超过容量，并且该笔交易的费用比当前交易池中列表最小值高，那么从交易池中移除交易费用最低的交易，为当前这一笔交易留出空间。<br>
    4.接着继续调用Overlaps方法检查该笔交易的Nonce值，确认该用户下的交易是否存在该笔交易。<br>
        <1>如果已经存在这笔交易，则删除之前的交易，并将该笔交易放入交易池中，然后返回。<br>
        <2>如果不存在，则调用enqueueTx将该笔交易放入交易池中。如果交易是本地发出的，则将发送者保存在交易池的local中。<br>
接下来看看validateTx方法会怎样验证交易的合法性。
```
// validateTx checks whether a transaction is valid according to the consensus
// rules and adheres to some heuristic limits of the local node (price and size).
    func (pool *TxPool) validateTx(tx *types.Transaction, local bool) error {
        // Heuristic limit, reject transactions over 32KB to prevent DOS attacks
        if tx.Size() > 32*1024 {
            return ErrOversizedData
        }
        // Transactions can't be negative. This may never happen using RLP decoded
        // transactions but may occur if you create a transaction using the RPC.
        if tx.Value().Sign() < 0 {
            return ErrNegativeValue
        }
        // Ensure the transaction doesn't exceed the current block limit gas.
        if pool.currentMaxGas < tx.Gas() {
            return ErrGasLimit
        }
        // Make sure the transaction is signed properly
        from, err := types.Sender(pool.signer, tx)
        if err != nil {
            return ErrInvalidSender
        }
        // Drop non-local transactions under our own minimal accepted gas price
        local = local || pool.locals.contains(from) // account may be local even if the transaction arrived from the network
        if !local && pool.gasPrice.Cmp(tx.GasPrice()) > 0 {
            return ErrUnderpriced
        }
        // Ensure the transaction adheres to nonce ordering
        if pool.currentState.GetNonce(from) > tx.Nonce() {
            return ErrNonceTooLow
        }
        // Transactor should have enough funds to cover the costs
        // cost == V + GP * GL
        if pool.currentState.GetBalance(from).Cmp(tx.Cost()) < 0 {
            return ErrInsufficientFunds
        }
        intrGas, err := IntrinsicGas(tx.Data(), tx.To() == nil, pool.homestead)
        if err != nil {
            return err
        }
        if tx.Gas() < intrGas {
            return ErrIntrinsicGas
        }
        return nil
    }
```
validateTx会验证一笔交易的以下几个特性：<br>
    1.首先验证这笔交易的大小，如果大于32kb则拒绝这笔交易，这样主要是为了防止DDOS攻击。<br>
    2.接着验证转账金额。如果金额小于0则拒绝这笔交易。<br>
    3.这笔交易的gas不能超过交易池的gas上限。<br>
    4.验证这笔交易的签名是否合法。<br>
    5.如果这笔交易不是来自本地并且这笔交易的gas小于当前交易池中的gas，则拒绝这笔交易。<br>
    6.当前用户的nonce如果大于这笔交易的nonce，则拒绝这笔交易。<br>
    7.当前用户的余额是否充足，如果不充足则拒绝该笔交易。<br>
    8.验证这笔交易的固有花费，如果小于交易池的gas，则拒绝该笔交易。<br>
以上就是在进行交易验证时所需验证的参数。这一系列的验证操作结束后，回到addTx的第二步。<br>
会判断replace。如果replace是false，则会执行promoteExecutables方法。<br>
promoteExecutables会将所有可处理的交易放入pending区，并移除所有非法的交易。
```
// promoteExecutables moves transactions that have become processable from the
// future queue to the set of pending transactions. During this process, all
// invalidated transactions (low nonce, low balance) are deleted.
    func (pool *TxPool) promoteExecutables(accounts []common.Address) {
        // Gather all the accounts potentially needing updates
        if accounts == nil {
            accounts = make([]common.Address, 0, len(pool.queue))
            for addr := range pool.queue {
                accounts = append(accounts, addr)
            }
        }
        // Iterate over all accounts and promote any executable transactions
        for _, addr := range accounts {
            list := pool.queue[addr]
            if list == nil {
                continue // Just in case someone calls with a non existing account
            }
            // Drop all transactions that are deemed too old (low nonce)
            for _, tx := range list.Forward(pool.currentState.GetNonce(addr)) {
                hash := tx.Hash()
                log.Trace("Removed old queued transaction", "hash", hash)
                delete(pool.all, hash)
                pool.priced.Removed()
            }
            // Drop all transactions that are too costly (low balance or out of gas)
            drops, _ := list.Filter(pool.currentState.GetBalance(addr), pool.currentMaxGas)
            for _, tx := range drops {
                hash := tx.Hash()
                log.Trace("Removed unpayable queued transaction", "hash", hash)
                delete(pool.all, hash)
                pool.priced.Removed()
                queuedNofundsCounter.Inc(1)
            }
            // Gather all executable transactions and promote them
            for _, tx := range list.Ready(pool.pendingState.GetNonce(addr)) {
                hash := tx.Hash()
                log.Trace("Promoting queued transaction", "hash", hash)
                pool.promoteTx(addr, hash, tx)
            }
            // Drop all transactions over the allowed limit
            if !pool.locals.contains(addr) {
                for _, tx := range list.Cap(int(pool.config.AccountQueue)) {
                    hash := tx.Hash()
                    delete(pool.all, hash)
                    pool.priced.Removed()
                    queuedRateLimitCounter.Inc(1)
                    log.Trace("Removed cap-exceeding queued transaction", "hash", hash)
                }
            }
            // Delete the entire queue entry if it became empty.
            if list.Empty() {
                delete(pool.queue, addr)
            }
        }
        // If the pending limit is overflown, start equalizing allowances
        pending := uint64(0)
        for _, list := range pool.pending {
            pending += uint64(list.Len())
        }
        if pending > pool.config.GlobalSlots {
            pendingBeforeCap := pending
            // Assemble a spam order to penalize large transactors first
            spammers := prque.New()
            for addr, list := range pool.pending {
                // Only evict transactions from high rollers
                if !pool.locals.contains(addr) && uint64(list.Len()) > pool.config.AccountSlots {
                    spammers.Push(addr, float32(list.Len()))
                }
            }
            // Gradually drop transactions from offenders
            offenders := []common.Address{}
            for pending > pool.config.GlobalSlots && !spammers.Empty() {
                // Retrieve the next offender if not local address
                offender, _ := spammers.Pop()
                offenders = append(offenders, offender.(common.Address))
    
                // Equalize balances until all the same or below threshold
                if len(offenders) > 1 {
                    // Calculate the equalization threshold for all current offenders
                    threshold := pool.pending[offender.(common.Address)].Len()
    
                    // Iteratively reduce all offenders until below limit or threshold reached
                    for pending > pool.config.GlobalSlots && pool.pending[offenders[len(offenders)-2]].Len() > threshold {
                        for i := 0; i < len(offenders)-1; i++ {
                            list := pool.pending[offenders[i]]
                            for _, tx := range list.Cap(list.Len() - 1) {
                                // Drop the transaction from the global pools too
                                hash := tx.Hash()
                                delete(pool.all, hash)
                                pool.priced.Removed()
    
                                // Update the account nonce to the dropped transaction
                                if nonce := tx.Nonce(); pool.pendingState.GetNonce(offenders[i]) > nonce {
                                    pool.pendingState.SetNonce(offenders[i], nonce)
                                }
                                log.Trace("Removed fairness-exceeding pending transaction", "hash", hash)
                            }
                            pending--
                        }
                    }
                }
            }
            // If still above threshold, reduce to limit or min allowance
            if pending > pool.config.GlobalSlots && len(offenders) > 0 {
                for pending > pool.config.GlobalSlots && uint64(pool.pending[offenders[len(offenders)-1]].Len()) > pool.config.AccountSlots {
                    for _, addr := range offenders {
                        list := pool.pending[addr]
                        for _, tx := range list.Cap(list.Len() - 1) {
                            // Drop the transaction from the global pools too
                            hash := tx.Hash()
                            delete(pool.all, hash)
                            pool.priced.Removed()
    
                            // Update the account nonce to the dropped transaction
                            if nonce := tx.Nonce(); pool.pendingState.GetNonce(addr) > nonce {
                                pool.pendingState.SetNonce(addr, nonce)
                            }
                            log.Trace("Removed fairness-exceeding pending transaction", "hash", hash)
                        }
                        pending--
                    }
                }
            }
            pendingRateLimitCounter.Inc(int64(pendingBeforeCap - pending))
        }
        // If we've queued more transactions than the hard limit, drop oldest ones
        queued := uint64(0)
        for _, list := range pool.queue {
            queued += uint64(list.Len())
        }
        if queued > pool.config.GlobalQueue {
            // Sort all accounts with queued transactions by heartbeat
            addresses := make(addresssByHeartbeat, 0, len(pool.queue))
            for addr := range pool.queue {
                if !pool.locals.contains(addr) { // don't drop locals
                    addresses = append(addresses, addressByHeartbeat{addr, pool.beats[addr]})
                }
            }
            sort.Sort(addresses)
    
            // Drop transactions until the total is below the limit or only locals remain
            for drop := queued - pool.config.GlobalQueue; drop > 0 && len(addresses) > 0; {
                addr := addresses[len(addresses)-1]
                list := pool.queue[addr.address]
    
                addresses = addresses[:len(addresses)-1]
    
                // Drop all transactions if they are less than the overflow
                if size := uint64(list.Len()); size <= drop {
                    for _, tx := range list.Flatten() {
                        pool.removeTx(tx.Hash())
                    }
                    drop -= size
                    queuedRateLimitCounter.Inc(int64(size))
                    continue
                }
                // Otherwise drop only last few transactions
                txs := list.Flatten()
                for i := len(txs) - 1; i >= 0 && drop > 0; i-- {
                    pool.removeTx(txs[i].Hash())
                    drop--
                    queuedRateLimitCounter.Inc(1)
                }
            }
        }
    }
```
这个方法首先会迭代所有当前账户的交易，检查当前交易的nonce。如果nonce太低，则删除该笔交易。（list.Forward方法）<br>
接下来检查余额不足或者gas不足的交易并删除。（list.Filter方法）<br>
然后将剩余的交易状态更新为pending并放在pending集合中。然后将当前消息池该用户的nonce值+1，接着广播TxPreEvent事件，告诉他们本地有一笔新的合法交易等待处理。（pool.promoteTx方法）<br>
接着检查消息池的pending列表是否超过容量，如果超过将进行扩容操作。如果一个账户进行的状态超过限制，从交易池中删除最先添加的交易。<br>
在promoteExecutable中有一个promoteTx方法，这个方法是将交易防区pending区方法中。在promoteTx方法中，最后一步执行的是一个Send方法。<br>
这个Send方法会同步将pending区的交易广播至它所连接到的节点，并返回通知到的节点的数量。<br>
然后被通知到的节点继续通知到它添加的节点，继而广播至全网。<br>
至此，发送交易就结束了。此时交易池中的交易等待挖矿打包处理。<br>
