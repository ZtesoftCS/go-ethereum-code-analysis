

![image](picture/sign_state_1.png)

![image](picture/sign_state_3.png)是t+1时刻的状态(account trie)。

![image](picture/sign_state_4.png)是状态转换函数，也可以理解为执行引擎。

![image](picture/sign_state_5.png) 是transaction，一次交易。

![image](picture/sign_state_6.png)

![image](picture/sign_state_7.png)  是区块级别的状态转换函数。

![image](picture/sign_state_8.png)  是区块，由很多交易组成。

![image](picture/sign_state_9.png)  0号位置的交易。

![image](picture/sign_state_10.png) 是块终结状态转换函数（一个奖励挖矿者的函数）。

![image](picture/sign_ether.png) Ether的标识。

![image](picture/sign_ether_value.png) Ethereum中所用到的各种单位与Wei的换算关系（例如：一个Finney对应10^15个Wei）。

![image](picture/sign_machine_state.png) machine-state

## 一些基本的规则

- 对于大多数的函数来说，都用大写字母来标识。
- 元组一般用大写字母来标识
- 标量或者固定大小的字节数组都用小写字母标识。 比如 n 代表交易的nonce， 有一些可能有例外，比如δ代表 一个给定指令需要的堆栈数据的多少。
- 变长的字节数组一般用加粗的小写字母。 比如 **o** 代表一个message call的输出数据。对于某些重要的也可能使用加粗的大写字母


![image](picture/sign_set_b.png) 字节序列
![image](picture/sign_set_p.png) 正整数
![image](picture/sign_set_b32.png) 32字节长度的字节序列
![image](picture/sign_set_p256.png) 小于 2^256 的正整数
**[ ]** 用于索引数组里面的对应元素
![image](picture/sign_stack.png) 代表机器堆栈(machine's stack)的第一个对象
![image](picture/sign_memory.png) 代表了机器内存(machine's memory)里面的前32个元素
![image](picture/sign_placeholder_1.png) 一个占位符号，可以是任意字符代表任意对象

![image](picture/sign_placeholder_2.png) 代表这个对象被修改后的值
![image](picture/sign_placeholder_3.png) 中间状态
![image](picture/sign_placeholder_4.png) 中间状态2
![image](picture/sign_func_1.png) ![image](picture/sign_func_2.png) 如果前面的f代表了一个函数， 那么后面的f*代表了一个相似的函数，不过是对内部的元素依次执行f的一个函数。

![image](picture/sign_last_item.png)  代表了列表里面的最后一个元素
![image](picture/sign_last_item_1.png)  代表了列表里面的最后一个元素
![image](picture/sign_seq_item.png)   求x的长度


![image](picture/sign_state_nonce.png)  a代表某个地址，代表某个账号的nonce
![image](picture/sign_state_balance.png) banlance 余额
![image](picture/sign_state_root.png)   storage trie 的 root hash
![image](picture/sign_state_code.png) Code的hash。 如果code是b 那么KEC(b)===这个hash


![image](picture/sign_l1.png)

![image](picture/sign_ls.png)  world state collapse function
![image](picture/sign_pa.png)


![image](picture/sign_math_any.png)  任意的 any
![image](picture/sign_math_or.png)   并集 or
![image](picture/sign_math_and.png)  交集 and

![image](picture/sign_homestead.png) Homestead
## 交易

![image](picture/sign_t_nonce.png) 交易的nonce
![image](picture/sign_t_gasprice.png) gasPrice
![image](picture/sign_t_gaslimit.png) gasLimit
![image](picture/sign_t_to.png) to
![image](picture/sign_t_value.png) value

![image](picture/sign_t_w.png)![image](picture/sign_t_tr.png)![image](picture/sign_t_ts.png)通过者三个值可以得到sender的地址

![image](picture/sign_t_ti.png) 合约的初始化代码
![image](picture/sign_t_data.png) 方法调用的入参
![image](picture/sign_t_lt.png)

## 区块头

![image](picture/sign_h_p.png)ParentHash
![image](picture/sign_h_o.png)OmmersHash
![image](picture/sign_h_c.png)beneficiary矿工地址
![image](picture/sign_h_r.png)stateRoot
![image](picture/sign_h_t.png)transactionRoot
![image](picture/sign_h_e.png)receiptRoot
![image](picture/sign_h_b.png)logsBloom
![image](picture/sign_h_d.png)难度
![image](picture/sign_h_i.png)number高度
![image](picture/sign_h_l.png)gasLimit
![image](picture/sign_h_g.png)gasUsed
![image](picture/sign_h_s.png)timestamp
![image](picture/sign_h_x.png)extraData
![image](picture/sign_h_m.png)mixHash
![image](picture/sign_h_n.png)nonce
## 回执

![image](picture/sign_r_i.png) 第i个交易的receipt

![image](picture/sign_receipt.png)
![image](picture/sign_r_state.png) 交易执行后的world-state
![image](picture/sign_r_gasused.png)交易执行后区块总的gas使用量
![image](picture/sign_r_bloom.png)本交易执行产生的所有log的布隆过滤数据
![image](picture/sign_r_log.png)交易产生的日志集合

![image](picture/sign_r_logentry.png) Log entry Oa日志产生的地址， Ot topic Od 时间

## 交易执行
![image](picture/sign_substate_a.png) substate
![image](picture/sign_substate_as.png) suicide set
![image](picture/sign_substate_al.png) log series
![image](picture/sign_substate_ar.png) refund balance

![image](picture/sign_gas_total.png) 交易过程中使用的总gas数量。
![image](picture/sign_gas_log.png)	 交易产生的日志。

![image](picture/sign_i_a.png) 执行代码的拥有者
![image](picture/sign_i_o.png) 交易的发起者
![image](picture/sign_i_p.png) gasPrice
![image](picture/sign_i_d.png) inputdata
![image](picture/sign_i_s.png) 引起代码执行的地址，如果是交易那么是交易的发起人
![image](picture/sign_i_v.png) value
![image](picture/sign_i_b.png) 需要执行的代码
![image](picture/sign_i_h.png) 当前的区块头
![image](picture/sign_i_e.png) 当前的调用深度


![image](picture/sign_exec_model.png) 执行模型 s suicide set; l 日志集合 **o** 输出 ; r refund

![image](picture/sign_exec_func.png) 执行函数

![image](picture/sign_m_g.png) 当前可用的gas
![image](picture/sign_u_pc.png) 程序计数器
![image](picture/sign_u_m.png) 内存内容
![image](picture/sign_u_i.png) 内存中有效的word数量
![image](picture/sign_u_s.png) 堆栈内容

![image](picture/sign_m_w.png) w代表当前需要执行的指令

![image](picture/sign_stack_removed.png) 指令需要移除的堆栈对象个数
![image](picture/sign_stack_added.png) 指令需要增加的堆栈对象个数
