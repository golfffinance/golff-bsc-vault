const REWARD_ADDRESS = '0x2C2c80ee9c246bBa6c488050B75c9a65584c4f8f';//todo
const FUNDATION_ADDRESS = '0x79006B8548326C71bbF57a4384843Df2f578381F';//todo
const BURN_ADDRESS = '0x87dE96c1658a37DfA46108A60Fd58e7B9224A4EE';//todo

// const unit = web3.utils.toBN(10 ** 18);

//todo  config earnLowerlimit need check before online
const GOF_VAULT = [
    // { token: 'USDT', symbol: 'USDT', earnLowerlimit: '0' },
    // { token: 'LINK', symbol: 'LINK', earnLowerlimit: '0' },
    // { token: 'CAKE-BNB', symbol: 'CAKE-BNB', earnLowerlimit: '0' },
    // { token: 'FIL', symbol: 'FIL', earnLowerlimit: '0' },
    { token: 'WBNB', symbol: 'WBNB', earnLowerlimit: '0' }
]

const GOF_STRATEGY_MDEX = [
    // {
    //     pid: 4, token: 'USDT', output: 'MDX', pool: '0xc48FE252Aa631017dF253578B1405ea399728A50'
    //     , router: '0x7DAe51BD3E3376B8c7c4900E9107f12Be3AF1bA8', hgofRouting: ['USDT', 'ETH'], tokenRouting: ['MDX', 'USDT']
    // }
]

const GOF_STRATEGY_MDEX_LP = [
    // {
    //     pid: 4, token: 'BUSD', output: 'MDX', liquidityAToken:'CAKE', liquidityBToken:'WBNB', pool: '0xc48FE252Aa631017dF253578B1405ea399728A50'
    //     , router: '0x7DAe51BD3E3376B8c7c4900E9107f12Be3AF1bA8', hgofRouting: ['MDX', 'BUSD', 'ETH'], swap2LiquidityARouting: ['MDX', 'CAKE'], swap2LiquidityBRouting:['MDX', 'WBNB']
    // }
]

const GOF_STRATEGY_CAKE_LP = [
    {
        pid: 1, token: 'CAKE-BNB', output: 'CAKE', liquidityAToken: 'CAKE', liquidityBToken: 'WBNB', pool: '0x73feaa1eE314F8c655E354234017bE2193C9E24E'
        , router: '0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F', hgofRouting: ['CAKE', 'ETH'], swap2LiquidityARouting: ['CAKE'], swap2LiquidityBRouting:['CAKE', 'WBNB']
    }
]

const GOF_STRATEGY_AUTO = [
    // {
    //     pid: 5, token: 'LINK', output: 'AUTO', pool: '0x0895196562C7868C5Be92459FaE7f877ED450452'
    //     , router: '0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F', hgofRouting: ['LINK', 'WBNB', 'ETH'], tokenRouting: ['AUTO', 'WBNB', 'LINK']
    // }
]

const GOF_STRATEGY_VENUS = [
    // {
    //     token: 'FIL', output: 'XVS', pool: '0xf91d58b5aE142DAcC749f58A49FCBac340Cb0343'
    //     , router: '0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F', hgofRouting: ['XVS', 'BUSD', 'ETH'], tokenRouting: ['XVS', 'WBNB', 'FIL']
    // },
    // {
    //     token: 'WBNB', output: 'XVS', pool: '0xA07c5b74C9B40447a954e1466938b865b6BBea36'
    //     , router: '0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F', hgofRouting: ['WBNB', 'ETH'], tokenRouting: ['XVS', 'WBNB']
    // }
]


module.exports = {
    REWARD_ADDRESS,
    FUNDATION_ADDRESS,
    BURN_ADDRESS,
    GOF_VAULT,
    GOF_STRATEGY_MDEX,
    GOF_STRATEGY_MDEX_LP,
    GOF_STRATEGY_CAKE_LP,
    GOF_STRATEGY_VENUS,
    GOF_STRATEGY_AUTO
}