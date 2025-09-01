use starknet::ContractAddress;
use crate::enums::poll_contract_enums::PollType;
use crate::structs::poll_contract_structs::{Poll, TokenGateConfig, Vote};


#[starknet::interface]
pub trait IPollingContract<TContractState> {
    /// Create a Yes/No poll
    fn create_poll(
        ref self: TContractState,
        title: ByteArray,
        description: ByteArray,
        poll_options: Array<ByteArray>,
        poll_type: PollType,
        end_time: Option<u64>,
        token_gate_config: Option<TokenGateConfig>,
    ) -> u256;

    /// Cast a vote
    fn vote(ref self: TContractState, poll_id: u256, option_index: u8);

    /// Close a poll (only creator)
    fn close_poll(ref self: TContractState, poll_id: u256);


    /// Read functions

    /// Get poll information
    fn get_poll(self: @TContractState, poll_id: u256) -> Poll;

    /// Check if user has voted
    fn has_voted(self: @TContractState, poll_id: u256, voter: ContractAddress) -> bool;

    /// Get user's vote
    fn get_user_vote(self: @TContractState, poll_id: u256, voter: ContractAddress) -> Vote;

    /// Get all active polls
    fn get_active_polls(self: @TContractState) -> Array<u256>;

    /// Get polls created by user
    fn get_polls_by_creator(self: @TContractState, creator: ContractAddress) -> Array<Poll>;

    /// Get total polls count
    fn get_total_polls(self: @TContractState) -> u256;
}
