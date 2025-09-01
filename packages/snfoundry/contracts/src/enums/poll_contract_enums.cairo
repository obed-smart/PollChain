

/// Poll types - for poll type
#[derive(Drop, Copy, Serde, starknet::Store)]
#[allow(starknet::store_no_default_variant)]
pub enum PollType {
    YesNo,
    MultipleChoice,
}



/// TOKEN GATING STRUCTURES
/// For poll that will required token gating
#[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
pub enum GateType {
    #[default]
    None,
    ERC20Token,
    ERC721NFT,
}