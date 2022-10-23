### Consensus Reactor 
共识reactor包含了用于管理Tendermint共识内部状态机的ConsensusState服务。在reacor开启时，它会创建一个广播的goroutine用来开启ConsensusState服务。因为每个peer都被加到了共识reactor中，它会创建（和管理）相对应的节点状态。会为每个peer开启以下三个routine：Gossip Data Routine，Gossip Data Routine，QueryMaj23Routine。共识Reactor会负责对来自于peer的信息进行解码，还有根据消息的类型和数据进行相关的处理，处理通常是更新相应peer的状态，还有对一些消息（ProposalMessage, BlockPartMessage and VoteMessage）进行转发给ConsensusState模块进行进一步的处理。
接下来我们将讲述共识reactor核心函数的部分。


#### ConsensusState 服务
Consensus State处理Tendermint BFT共识算法。它处理投票，提议，达成共识，提交块到链上，把以上信息和ABCI App进行交互。内部状态机接受输入从对等节点，内部验证者和定时器。

在内部共识状态上我们有以下的执行单元：超时Ticker和接受Routine。超时Ticker是个定时器，制定在哪些高度/轮次/step的情况下超时。

#### Receive Routine of the ConsensusState service 
Receive Routine of the ConsensusState处理那些可能导致内部共识状态改变的信息。它是唯一一个更新RoundState（内部共识状态）对象的routine。更新（状态转移）在超时，完成提议，大于2/3大多数投票的情况下产生。它接受消息的来源有：peers，内部验证者，超时器，接受到消息后会激活相应的处理器处理，有可能会更新RoundState。协议的具体实现在Receive Routine。为了理解必须充分了解到Receive Routine管理和更新RoundState数据结构，然后利用gossip routine来决定那些信息需要发送给peer去处理。

#### Round State
RoundState定义了内部共识状态。它包括了高度，轮次，轮次的哪一步，当下的验证者集合，提议和提议的块，锁定的轮次和被锁定的块，接受到的投票集合，上一个块的commit和上一个块的验证人集合。

```
type RoundState struct {
    Height             int64 
    Round              int
    Step               RoundStepType
    Validators         ValidatorSet
    Proposal           Proposal
    ProposalBlock      Block
    ProposalBlockParts PartSet
    LockedRound        int
    LockedBlock        Block
    LockedBlockParts   PartSet
    Votes              HeightVoteSet
    LastCommit         VoteSet 
    LastValidators     ValidatorSet
}    
```

在内部，共识按照以下状态进行这状态的转换。
- RoundStepNewHeight
- RoundStepNewRound
- RoundStepPropose
- RoundStepProposeWait
- RoundStepPrevote
- RoundStepPrevoteWait
- RoundStepPrecommit
- RoundStepPrecommitWait
- RoundStepCommit 


#### Peer Round State
Peer round state包含一个节点的已知状态。当共识Reactor的Receiv Routine接受到信息时对其状态进行更新，并通过GossipRoutine发送信息给对等节点。

```
type PeerRoundState struct {
    Height                   int64               // Height peer is at
    Round                    int                 // Round peer is at, -1 if unknown.
    Step                     RoundStepType       // Step peer is at
    Proposal                 bool                // True if peer has proposal for this round
    ProposalBlockPartsHeader PartSetHeader 
    ProposalBlockParts       BitArray       
    ProposalPOLRound         int                 // Proposal's POL round. -1 if none.
    ProposalPOL              BitArray            // nil until ProposalPOLMessage received.
    Prevotes                 BitArray            // All votes peer has for this round
    Precommits               BitArray            // All precommits peer has for this round
    LastCommitRound          int                 // Round of commit for last height. -1 if none.
    LastCommit               BitArray            // All commit precommits of commit for last height.
    CatchupCommitRound       int                 // Round that we have commit for. Not necessarily unique. -1 if none.
    CatchupCommit            BitArray            // All commit precommits peer has for this height & CatchupCommitRound
}
 
```

#### Receive method of Consensus reactor 
Consensus reactor的入口是receive方法。当来自于一个对等节点的消息被接受时，通常情况下相应节点的round state会被改变成相应的状态，一些消息会被发送给进步的进行处理，是一个ConsensusState服务的一个实例。在Consensus Reactor的receive方法中我们为每个消息类型都定义了一个消息处理方法。在以下的消息处理器中，rs,prs分别标示了Roundstate和PeerRoundState。


#### NewRoundStepMessage handler 

```
handleMessage(msg):
    if msg is from smaller height/round/step then return
    // Just remember these values.
    prsHeight = prs.Height
    prsRound = prs.Round
    prsCatchupCommitRound = prs.CatchupCommitRound
    prsCatchupCommit = prs.CatchupCommit

    Update prs with values from msg
    if prs.Height or prs.Round has been updated then
        reset Proposal related fields of the peer state 
    if prs.Round has been updated and msg.Round == prsCatchupCommitRound then
        prs.Precommits = psCatchupCommit
    if prs.Height has been updated then 
        if prsHeight+1 == msg.Height && prsRound == msg.LastCommitRound then
            prs.LastCommitRound = msg.LastCommitRound
            prs.LastCommit = prs.Precommits
        } else {
            prs.LastCommitRound = msg.LastCommitRound
            prs.LastCommit = nil
        }
        Reset prs.CatchupCommitRound and prs.CatchupCommit
```


#### CommitStepMessage handler 

```
handleMessage(msg):
    if prs.Height == msg.Height then 
        prs.ProposalBlockPartsHeader = msg.BlockPartsHeader
        prs.ProposalBlockParts = msg.BlockParts
```


#### HasVoteMessage handler 

```
handleMessage(msg):
    if prs.Height == msg.Height then 
        prs.setHasVote(msg.Height, msg.Round, msg.Type, msg.Index)
```


#### VoteSetMaj23Message handler 

```
handleMessage(msg):
    if prs.Height == msg.Height then
        Record in rs that a peer claim to have ⅔ majority for msg.BlockID
        Send VoteSetBitsMessage showing votes node has for that BlockId 
 
```

#### ProposalMessage handler 

```
handleMessage(msg):
    if prs.Height != msg.Height || prs.Round != msg.Round || prs.Proposal then return    
    prs.Proposal = true
    prs.ProposalBlockPartsHeader = msg.BlockPartsHeader
    prs.ProposalBlockParts = empty set    
    prs.ProposalPOLRound = msg.POLRound
    prs.ProposalPOL = nil 
    Send msg through internal peerMsgQueue to ConsensusState service
```


#### ProposalPOLMessage handler 
 
```
handleMessage(msg):
    if prs.Height != msg.Height or prs.ProposalPOLRound != msg.ProposalPOLRound then return
    prs.ProposalPOL = msg.ProposalPOL
```

#### BlockPartMessage handler 
```
handleMessage(msg):
    if prs.Height != msg.Height || prs.Round != msg.Round then return
    Record in prs that peer has block part msg.Part.Index 
    Send msg trough internal peerMsgQueue to ConsensusState service
 
```

#### VoteMessage handler 

```
handleMessage(msg):
    Record in prs that a peer knows vote with index msg.vote.ValidatorIndex for particular height and round
    Send msg trough internal peerMsgQueue to ConsensusState service
```

#### VoteSetBitsMessage handler 

```
handleMessage(msg):
    Update prs for the bit-array of votes peer claims to have for the msg.BlockID
```

#### Gossip Data Routine

它通过DataChannel发送如下的消息给对等节点：BlockPartMessage, ProposalMessage and ProposalPOLMessage。GossipData routine基于RoundState（rs）和已知的PeerRoundstate（prs），routine按照如下逻辑进行不停的重复：


```
1a) if rs.ProposalBlockPartsHeader == prs.ProposalBlockPartsHeader and the peer does not have all the proposal parts then
        Part = pick a random proposal block part the peer does not have 
        Send BlockPartMessage(rs.Height, rs.Round, Part) to the peer on the DataChannel 
        if send returns true, record that the peer knows the corresponding block Part
        Continue  

1b) if (0 < prs.Height) and (prs.Height < rs.Height) then
        help peer catch up using gossipDataForCatchup function
        Continue

1c) if (rs.Height != prs.Height) or (rs.Round != prs.Round) then 
        Sleep PeerGossipSleepDuration
        Continue   

//  at this point rs.Height == prs.Height and rs.Round == prs.Round
1d) if (rs.Proposal != nil and !prs.Proposal) then 
        Send ProposalMessage(rs.Proposal) to the peer
        if send returns true, record that the peer knows Proposal
        if 0 <= rs.Proposal.POLRound then
        polRound = rs.Proposal.POLRound 
        prevotesBitArray = rs.Votes.Prevotes(polRound).BitArray() 
        Send ProposalPOLMessage(rs.Height, polRound, prevotesBitArray)
        Continue  

2)  Sleep PeerGossipSleepDuration 
```
#### Gossip Data For Catchup 
这个函数用来帮助节点赶上整个网络的状态（prs.Height < rs.Height），逻辑如下：

```
if peer does not have all block parts for prs.ProposalBlockPart then 
    blockMeta =  Load Block Metadata for height prs.Height from blockStore
    if (!blockMeta.BlockID.PartsHeader == prs.ProposalBlockPartsHeader) then
        Sleep PeerGossipSleepDuration
    return
    Part = pick a random proposal block part the peer does not have 
    Send BlockPartMessage(prs.Height, prs.Round, Part) to the peer on the DataChannel 
    if send returns true, record that the peer knows the corresponding block Part
    return
else Sleep PeerGossipSleepDuration 

```

#### Gossip Votes Routine 

被用来在VoteChannel发送VoteMessage。它也是基于本地RoundState（rs）和已知节点的PeerRoundstate（prs），routine按照如下逻辑进行不停的重复：

```
1a) if rs.Height == prs.Height then
        if prs.Step == RoundStepNewHeight then    
            vote = random vote from rs.LastCommit the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue

        if prs.Step <= RoundStepPrevote and prs.Round != -1 and prs.Round <= rs.Round then                 
            Prevotes = rs.Votes.Prevotes(prs.Round)
            vote = random vote from Prevotes the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue

        if prs.Step <= RoundStepPrecommit and prs.Round != -1 and prs.Round <= rs.Round then   
            Precommits = rs.Votes.Precommits(prs.Round) 
            vote = random vote from Precommits the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue

        if prs.ProposalPOLRound != -1 then 
            PolPrevotes = rs.Votes.Prevotes(prs.ProposalPOLRound)
            vote = random vote from PolPrevotes the peer does not have  
            Send VoteMessage(vote) to the peer 
            if send returns true, continue         

1b)  if prs.Height != 0 and rs.Height == prs.Height+1 then
        vote = random vote from rs.LastCommit peer does not have  
        Send VoteMessage(vote) to the peer 
        if send returns true, continue

1c)  if prs.Height != 0 and rs.Height >= prs.Height+2 then
        Commit = get commit from BlockStore for prs.Height  
        vote = random vote from Commit the peer does not have  
        Send VoteMessage(vote) to the peer 
        if send returns true, continue

2)   Sleep PeerGossipSleepDuration 
 
```

#### QueryMaj23Routine
是用来发送VoteSetMaj23Message的。VoteSetMaj23Message标示给定的BlockID有了大于2/3的投票。它也是基于本地RoundState（rs）和已知节点的PeerRoundstate（prs），routine按照如下逻辑进行不停的重复：

```
1a) if rs.Height == prs.Height then
        Prevotes = rs.Votes.Prevotes(prs.Round)
        if there is a ⅔ majority for some blockId in Prevotes then
        m = VoteSetMaj23Message(prs.Height, prs.Round, Prevote, blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

1b) if rs.Height == prs.Height then
        Precommits = rs.Votes.Precommits(prs.Round)
        if there is a ⅔ majority for some blockId in Precommits then
        m = VoteSetMaj23Message(prs.Height,prs.Round,Precommit,blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

1c) if rs.Height == prs.Height and prs.ProposalPOLRound >= 0 then
        Prevotes = rs.Votes.Prevotes(prs.ProposalPOLRound)
        if there is a ⅔ majority for some blockId in Prevotes then
        m = VoteSetMaj23Message(prs.Height,prs.ProposalPOLRound,Prevotes,blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

1d) if prs.CatchupCommitRound != -1 and 0 < prs.Height and 
        prs.Height <= blockStore.Height() then 
        Commit = LoadCommit(prs.Height)
        m = VoteSetMaj23Message(prs.Height,Commit.Round,Precommit,Commit.blockId)
        Send m to peer
        Sleep PeerQueryMaj23SleepDuration

2)  Sleep PeerQueryMaj23SleepDuration
```

#### Broadcast routine 
Broadcast routine订阅了一个内部事件总线，用来接受新的轮次步骤，投票消息和提议心跳消息，并把接受到的事件广播给对等节点。它接受到new round state事件时，广播NewRoundStepMessage或者CommitStepMessage。请注意，广播这些消息时不会根据PeerRoundState；它时把消息放到到StateChannel上。根据接受到的VoteMessage它广播HasVoteMessage消息给它的对等节点在StateChannel上。ProposalHeartbeatMessage以同样的路径发送到StateChannel。
