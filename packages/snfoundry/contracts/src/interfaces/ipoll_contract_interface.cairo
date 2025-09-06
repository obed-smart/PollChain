// ipoll_contract_interface.cairo

//! # pollContract Interface
//!
//! This file defines the external interface for the PollContract.
//! It includes functions for creating polls, voting, closing polls, and retrieving poll
//! information.

use starknet::ContractAddress;
use crate::enums::poll_contract_enums::PollType;
use crate::structs::poll_contract_structs::{Poll, PollResult, Vote, Winner};
use crate::structs::utils_structs::TokenGateConfig;


#[starknet::interface]
pub trait IPollingContract<TContractState> {
    /// Create a poll in the storage slot
        ///
        /// # Parameters
        /// - `title`: The title of the poll
        /// - `description`: The description of the poll
        /// - `poll_options`: The options for the poll (2 for Yes/No, 3-10 for MultipleChoice)
        /// - `poll_type`: The type of the poll
        /// - `end_time`: Optional end time for the poll
        /// - `token_gate_config`: Optional token gating configuration
        ///
        /// # Behaviour
        /// - Validates input parameters based on poll type and token gating
        /// - Creates a new poll and stores it
        /// - Updates relevant mappings and counters
        /// - write to the storage slot
        /// - Emits a `PollCreated` event
        ///
        /// # Requirements
        /// - The caller must not be the zero address
        /// - For Yes/No polls, exactly 2 options must be provided
        /// - For MultipleChoice polls, between 3 and 10 options must be provided
        /// - If an end time is provided, it must be in the future
        /// - If token gating is enabled, the configuration must be valid
        /// - The creator must meet the token gating requirements if enabled
        /// # Returns
        /// - The ID of the newly created poll
       
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
    fn get_polls_by_creator(
        self: @TContractState, creator: ContractAddress, page: u256, page_size: u256,
    ) -> Array<Poll>;

    /// Get total polls count
    fn get_total_polls(self: @TContractState) -> u256;

    /// Get total vote per poll
    fn get_poll_total_votes(self: @TContractState, poll_id: u256) -> u64;

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
    fn get_poll_results(self: @TContractState, poll_id: u256) -> Array<PollResult>;

    // get voter poll count
    fn get_voter_poll_count(self: @TContractState, poll_id: u256, voter: ContractAddress) -> u256;

    // get voter voted polls
    fn get_voter_polls(
        self: @TContractState, voter: ContractAddress, page: u256, page_size: u256,
    ) -> Array<Poll>;
}
