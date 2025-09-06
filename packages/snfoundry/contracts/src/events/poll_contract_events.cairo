use starknet::ContractAddress;
use crate::enums::poll_contract_enums::{GateType, PollType};

/// Event to emit when i new contract is created
#[derive(Drop, starknet::Event)]
pub struct PollCreated {
    #[key]
    pub poll_id: u256,
    #[key]
    pub creator: ContractAddress,
    pub title: ByteArray,
    pub poll_type: PollType,
    pub created_at: u64,
    pub end_time: Option<u64>,
    pub is_token_gated: bool,
    pub gate_type: GateType,
    pub token_address: ContractAddress,
}

// Event to Emit when a vote is casted
#[derive(Drop, starknet::Event)]
pub struct VoteCasted {
    #[key]
    pub poll_id: u256,
    #[key]
    pub voter: ContractAddress,
    pub option_index: u8,
    pub timestamp: u64,
}


#[derive(Drop, starknet::Event)]
pub struct PollEnded {
    #[key]
    pub poll_id: u256,
    pub total_votes: u64,
    pub winning_option: u32,
    pub ended_at: u64,
}

