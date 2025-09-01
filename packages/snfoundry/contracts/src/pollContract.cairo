#[starknet::contract]
pub mod PollingContract {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::enums::poll_contract_enums::{GateType, PollType};
    use crate::events::poll_contract_events::{PollCreated, PollEnded, VoteCasted};
    use crate::interfaces::ipoll_contract_interface::IPollingContract;
    use crate::structs::poll_contract_structs::{Poll, TokenGateConfig, Vote};

    // All event to emit when action happens
    #[derive(Drop, starknet::Event)]
    #[event]
    pub enum Event {
        PollCreated: PollCreated,
        VoteCasted: VoteCasted,
        PollEnded: PollEnded,
    }

    #[storage]
    struct Storage {
        //core storage
        polls: Map<u256, Poll>, // Map the poll_id to the Poll struct
        voters: Map<(u256, ContractAddress), Vote>,
        user_has_voted: Map<(u256, ContractAddress), bool>,
        // poll management
        active_polls: Map<u256, bool>,
        polls_by_creator: Map<(ContractAddress, u256), u256>,
        creator_poll_count: Map<ContractAddress, u256>,
        /// implemented this storage slot because the Poll struct does not Implement Array<T> Or
        /// Span<T>
        poll_options: Map<
            (u256, usize), ByteArray,
        >, // Map the poll_id --> option_index --> the text content 
        poll_option_votes: Map<
            (u256, u32), u256,
        >, // Map the poll_id --> the option --> total vote on each option
        // Global counters

        //
        next_poll_id: u256, // the general poll_id
        total_polls: u256, // the tot
        total_active_polls: u256,
    }


    #[constructor]
    fn constructor(ref self: ContractState) {
        self.next_poll_id.write(1);
        self.total_polls.write(0);
        self.total_active_polls.write(0);
    }

    /// main logic implementation
    #[abi(embed_v0)]
    impl Pollingimpl of IPollingContract<ContractState> {
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
            ref self: ContractState,
            title: ByteArray,
            description: ByteArray,
            poll_options: Array<ByteArray>,
            poll_type: PollType, // Add this parameter
            end_time: Option<u64>,
            token_gate_config: Option<TokenGateConfig>,
        ) -> u256 {
            let creator = get_caller_address();

            // allow creating poll only if the creator is not zero address
            assert(!creator.is_zero(), 'caller cannot be zero address');

            // Different validation based on poll type
            match poll_type {
                PollType::YesNo => { assert(poll_options.len() == 2, 'Need exactly 2 for YesNo'); },
                PollType::MultipleChoice => {
                    assert(poll_options.len() >= 3, 'MultipleChoice needs 3 or more');
                    assert(poll_options.len() <= 10, 'MultipleChoice max 10');
                },
            }

            // validate the endtime to know if it Present or Not --> Option<T>
            let final_end_time = match end_time {
                Option::Some(time) => {
                    let current_time = get_block_timestamp();
                    assert(time > current_time, 'end time must be in future');
                    time
                },
                Option::None => 0,
            };

            // get the global next_poll_id
            let poll_id = self.next_poll_id.read();

            /// process the token gating configuration
            /// if token_gate_config.is_some()
            /// then validate the configuration
            /// else set default values
            let (is_token_gated, gate_type, token_address, minimum_balance, required_nft_id) =
                match token_gate_config {
                Some(config) => {
                    if config.enabled {
                        // validate if the creator meets the gating requirements

                        match config.gate_type {
                            GateType::ERC20Token => {
                                /// allow only if the token address is not zero
                                assert(
                                    !config.token_address.is_zero(), 'Token address cannot be zero',
                                );
                                /// allow only if the minimum balance is > zero
                                assert(
                                    config.minimum_balance > 0, 'Minimum balance must be > zero',
                                );
                                (
                                    true,
                                    config.gate_type,
                                    config.token_address,
                                    config.minimum_balance,
                                    Option::None,
                                )
                            },
                            GateType::ERC721NFT => {
                                /// allow only if the token address is not zero
                                assert(
                                    !config.token_address.is_zero(), 'Token address cannot be zero',
                                );

                                /// allow only if the nft id is not zero when provided
                                if let Option::Some(id) = config.required_nft_id {
                                    assert(id != Zero::zero(), 'Required NFT ID cannot be zero');
                                }

                                let min_nfts = if config.minimum_balance == 0 {
                                    1
                                } else {
                                    config.minimum_balance
                                };

                                (
                                    true,
                                    config.gate_type,
                                    config.token_address,
                                    min_nfts,
                                    config.required_nft_id,
                                )
                            },
                            GateType::None => {
                                (false, GateType::None, Zero::zero(), 0, Option::None)
                            },
                        }
                    } else {
                        (false, GateType::None, Zero::zero(), 0, Option::None)
                    }
                },
                None => { (false, GateType::None, Zero::zero(), 0, Option::None) },
            };

            // create a new poll instance
            let poll = Poll {
                poll_id: poll_id,
                creator: creator,
                title: title.clone(),
                description: description,
                poll_type: poll_type,
                created_at: get_block_timestamp(),
                end_time: final_end_time,
                total_votes: 0,
                is_token_gated: is_token_gated,
                gate_type: gate_type,
                token_address: token_address,
                minimum_balance: minimum_balance,
                required_nft_id: required_nft_id,
            };

            // Store poll options
            let mut index: u32 = 0;
            for option in poll_options {
                self.poll_options.write((poll_id, index), option);
                self.poll_option_votes.write((poll_id, index), 0);
                index += 1;
            }

            // Store the poll
            self.polls.write(poll_id, poll);
            self.active_polls.write(poll_id, true);

            // Update creator mappings
            let creator_count = self.creator_poll_count.read(creator);

            self.polls_by_creator.write((creator, creator_count + 1), poll_id);
            self.creator_poll_count.write(creator, creator_count + 1);

            // Update counters
            self.next_poll_id.write(poll_id + 1);
            self.total_polls.write(self.total_polls.read() + 1);
            self.total_active_polls.write(self.total_active_polls.read() + 1);

            // Emit event
            self
                .emit(
                    Event::PollCreated(
                        PollCreated {
                            poll_id: poll_id,
                            creator: creator,
                            title: title,
                            poll_type: poll_type,
                            created_at: get_block_timestamp(),
                            end_time: final_end_time,
                            is_token_gated: is_token_gated,
                            gate_type: gate_type,
                            token_address: token_address,
                        },
                    ),
                );

            poll_id
        }


        /// Cast a vote
        ///
        /// # Parameter
        /// - `poll_id`: The poll id use to identify each poll during creation
        /// - `option_index`: The index of the option being voted for (0-based)
        ///
        /// # Requirements
        /// - The poll must be active and not ended.
        /// - The voter must not have voted already.
        /// - If the poll is token-gated, the voter must meet the token requirements.
        ///
        /// # Behavior
        /// - Records the vote.
        /// - Increments the vote count for the selected option.
        /// - Increments the total votes for the poll.
        /// - Emits a `VoteCast` event.
        fn vote(ref self: ContractState, poll_id: u256, option_index: u8) {
            let voter = get_caller_address();
            let timestamp = get_block_timestamp();

            // Get poll instance
            let mut poll = self.polls.read(poll_id);

            /// allow voting only the voter is not zero address
            assert(!voter.is_zero(), 'Voter cannot be zero');

            /// allow voting only if the poll exist
            assert(poll.poll_id == poll_id, 'Poll does not exist');

            /// allow to vote only if the poll is still active
            assert(self.active_polls.read(poll_id), 'Poll is not active');

            /// allow to vote only if not voted before
            assert(!self.user_has_voted.read((poll_id, voter)), 'Already voted');

            ///
            if poll.end_time != 0 {
                assert(timestamp <= poll.end_time, 'Poll has ended');
            }

            if poll.is_token_gated { // validate
            }

            let options_count = self.poll_option_votes.read((poll_id, option_index.into()));
            let total_polls = self.total_polls.read();

            self.poll_option_votes.write((poll_id, option_index.into()), options_count + 1);

            self.total_polls.write(total_polls + 1);

            let updated_poll = Poll { total_votes: poll.total_votes + 1, ..poll };
            self.polls.write(poll_id, updated_poll);

            // Create vote record
            let vote = Vote { voter: voter, option_index: option_index, timestamp: timestamp };

            // Store the vote
            self.voters.write((poll_id, voter), vote);
            self.user_has_voted.write((poll_id, voter), true);

            // Emit event
            self
                .emit(
                    Event::VoteCasted(
                        VoteCasted {
                            poll_id: poll_id,
                            voter: voter,
                            option_index: option_index,
                            timestamp: timestamp,
                        },
                    ),
                )
        }

        /// Close a poll (only creator)
        fn close_poll(ref self: ContractState, poll_id: u256) {}


        /// Read functions

        /// Get poll information
        fn get_poll(self: @ContractState, poll_id: u256) -> Poll {
            let poll = self.polls.read(poll_id);
            assert(poll.poll_id == poll_id, 'Poll does not exist');
            poll
        }

        /// Check if user has voted
        fn has_voted(self: @ContractState, poll_id: u256, voter: ContractAddress) -> bool {
            self.user_has_voted.read((poll_id, voter))
        }

        /// Get user's vote
        fn get_user_vote(self: @ContractState, poll_id: u256, voter: ContractAddress) -> Vote {
            self.voters.read((poll_id, voter))
        }

        /// Get all active polls
        fn get_active_polls(self: @ContractState) -> Array<u256> {
            let mut active_polls = ArrayTrait::new();
            let total = self.total_polls.read();

            let mut id: u256 = 1;

            while id != total {
                if self.active_polls.read(id) {
                    active_polls.append(id);
                }
                id += 1;
            }

            active_polls
        }

        /// Get polls created by user
        ///
        /// # Parameters
        /// - `creator`: The address of the poll creator
        ///
        /// # Behaviour
        /// - Retrieves all polls created by the specified creator
        ///
        /// # Returns
        /// - An array of `Poll` structs created by the specified creator
        fn get_polls_by_creator(self: @ContractState, creator: ContractAddress) -> Array<Poll> {
            let mut creator_polls = ArrayTrait::new();
            let count = self.creator_poll_count.read(creator);
            let mut index: u256 = 1;

            while index != count {
                let poll_id = self.polls_by_creator.read((creator, index));
                let poll = self.polls.read(poll_id);
                creator_polls.append(poll); 
                index += 1;
            }

            creator_polls
        }

        /// Get total polls count
        fn get_total_polls(self: @ContractState) -> u256 {
            self.total_polls.read()
        }
    }
}
