# Sig 库概要

sig库是一个服务于 cosmos sdk的 转账数据签名的node库

# Sig 库支持的功能

1. 给定助记词生成钱包 包括(私钥，公钥，地址)
2. 给定公钥解析地址
3. 结构化转账数据
4. 签名转账数据
5. 验证一笔转账的签名
6. 构建一笔待广播的转账
# Sig 库不支持的功能

1. 生成助记词
2. 存储key或者其他密码
3. 从链上获取数据
4. 广播交易
# Msg Type

Sig 库中核心是构建转账数据，其中要使用正确的msg type ，而msg type 是gaia与tendermint通信时在gaia中使用 codec注册时定义的name参数。以下是支持的 msg type

cosmos-sdk/MsgSend

cosmos-sdk/MsgMultiSend

cosmos-sdk/MsgCreateValidator

cosmos-sdk/MsgEditValidator

cosmos-sdk/MsgDelegate

cosmos-sdk/MsgUndelegate

cosmos-sdk/MsgBeginRedelegate

cosmos-sdk/MsgWithdrawDelegationReward

cosmos-sdk/MsgWithdrawValidatorCommission

cosmos-sdk/MsgModifyWithdrawAddress

cosmos-sdk/MsgSubmitProposal

cosmos-sdk/MsgDeposit

cosmos-sdk/MsgVote

cosmos-sdk/MsgUnjail

有msg type 就有 msg，msg type 和msg的结构要一一对应，msg 结构的定义在cosmos sdk 的各个module中，具体位于 types/msgs.go 文件中。

# Sig 地址生成和转账

1. 需要预先启动gaia 和 gaia 的lcd 服务
1. 创建一个js文件并将下面代码复制进去
2. 在js文件所在目录中安装 sig 和 node-fetch 库

const sig = require('@tendermint/sig')

const fetch = require('node-fetch').default;

// 根据mnemonic构成钱包

const mnemonic = 'settle vessel enact demise infant sunny abuse very famous apology motor guitar among body theory private brother prefer march rocket close execute response truth';

const wallet = sig.createWalletFromMnemonic(mnemonic); // BIP39 mnemonic string

// console.log(wallet)

// 根据钱包公钥解析地址

const address = sig.createAddress(wallet.publicKey);

// console.log(address)

// 转账信息构建

const rpcUrl = "http://127.0.0.1:1317"

const chainId = "testchain"

let Cosmos = function(url, chainId) {

	this.url = url;

	this.chainId = chainId;

}

Cosmos.prototype.getAccounts = function(address) {

	const accountsApi = "/auth/accounts/";

	return fetch(this.url + accountsApi + address)

	.then(response => response.json())

}

Cosmos.prototype.broadcast = function(signedTx) {

	const broadcastApi = "/txs";

	return fetch(this.url + broadcastApi, {

		method: 'POST',

		headers: {

			'Content-Type': 'application/json'

		},

		body: JSON.stringify(signedTx)

	})

	.then(response => response.json())

}

const CosmosNet = new Cosmos(rpcUrl, chainId)

CosmosNet.getAccounts(address).then(data => {

    

	let tx = {

		msg: [

			{

				type: "cosmos-sdk/MsgSend",

				value: {

					amount: [

						{

							amount: String(3),

							denom: "stake"

						}

					],

					from_address: address,

					to_address: "cosmos1v5hcfplyy0umj3zaqnh7jpneapecy865gl4x4l"

				}

			}

		],

		fee: { amount: [ { amount: String(1), denom: "stake" } ], gas: String(200000) },

		memo: ""

    };

    

    const signMeta = {

        account_number: String(data.result.value.account_number),

        chain_id:       chainId,

        sequence:       String(data.result.value.sequence)

    };

    

    const stdTx = sig.createBroadcastTx(sig.signTx(tx, signMeta, wallet));

    // console.log(stdTx);

	CosmosNet.broadcast(stdTx).then(response => console.log(response));

})





