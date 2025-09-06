use starknet::ContractAddress;
use crate::enums::poll_contract_enums::{GateType, PollType};


/// Poll information - A type of poll struct
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct Poll {
    pub poll_id: u256,
    pub creator: ContractAddress,
    pub title: ByteArray,
    pub description: ByteArray,
    pub poll_type: PollType,
    pub created_at: u64,
    pub end_time: Option<u64>,
    pub is_active: bool,
    pub total_votes: u64,
    pub num_options: u32,
    /// Configuration for token gating
    pub is_token_gated: bool,
    pub gate_type: GateType,
    pub token_address: ContractAddress,
    pub minimum_balance: u32,
    pub required_nft_id: Option<u256>,
}

/// type for Individual vote record for each person that vote
#[derive(Drop, Serde, starknet::Store)]
pub struct Vote {
    pub voter: ContractAddress,
    pub option_index: u8,
    pub timestamp: u64,
}


/// winner option data
#[derive(Drop, Serde)]
pub struct Winner {
    pub option_index: u32,
    pub vote_count: u256,
}

/// Result struct for poll results
#[derive(Drop, Serde)]
pub struct PollResult {
    pub option_index: u32,
    pub votes: u256,
    pub percentage: u256,
}
