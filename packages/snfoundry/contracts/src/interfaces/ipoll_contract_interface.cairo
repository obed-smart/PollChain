use starknet::ContractAddress;
use crate::enums::poll_contract_enums::PollType;
use crate::structs::poll_contract_structs::{Poll, TokenGateConfig, Vote, Winner,OptionsResult};


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
    fn get_active_poll(self: @TContractState, poll_id: u256) -> bool;

    /// Get polls created by user
    fn get_polls_by_creator(self: @TContractState, creator: ContractAddress) -> Array<Poll>;

    /// Get total polls count
    fn get_total_polls(self: @TContractState) -> u256;

    /// Get total vote per poll
    fn get_poll_total_votes(self: @TContractState, poll_id: u256) -> u256;

    /// Get total vote per poll_option
    ///
    fn get_total_votes_per_poll_option(
        self: @TContractState, poll_id: u256, option_index: u8,
    ) -> u256;

    /// Get creator total votes count
    fn get_creator_total_votes(self: @TContractState, creator: ContractAddress) -> u256;

    /// Get poll_voters
    fn get_poll_voters(self: @TContractState, poll_id: u256) -> Array<ContractAddress>;

    /// calculate the winner option
     fn calculate_winner(self: @TContractState, poll_id: u256) -> Winner;

     /// Get poll results
     fn get_poll_results(self: @TContractState, poll_id: u256) -> Array<OptionsResult>;
}
