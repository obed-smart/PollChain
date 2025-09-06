#[starknet::contract]
pub mod PollingContract {
    use core::cmp::min;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_caller_address};
    use crate::enums::poll_contract_enums::PollType;
    use crate::events::poll_contract_events::{PollCreated, PollEnded, VoteCasted};
    use crate::interfaces::ipoll_contract_interface::IPollingContract;
    use crate::structs::poll_contract_structs::{Poll, PollResult, Vote, Winner};
    use crate::structs::utils_structs::TokenGateConfig;
    use crate::utils::validators::{
        process_and_validate_token_gate_config, validate_voter_eligibility,
    };


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);


    // Ownable Mixin
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        //core storage

        // Map the poll_id to the Poll struct
        polls: Map<u256, Poll>,
        /// Map the poll_id and the voters address to the vote
        voters: Map<(u256, ContractAddress), Vote>,
        /// Map the poll_id and the voters address to whether they have voted
        user_has_voted: Map<(u256, ContractAddress), bool>,
        /// # poll management
        /// - Map the poll_id to weather true or false
        active_polls: Map<u256, bool>,
        /// - Map the poll creator address and the index to the poll_id
        polls_by_creator: Map<(ContractAddress, u256), u256>,
        ///- Map the creator address to the total amount of polls created
        creator_poll_count: Map<ContractAddress, u256>,
        /// - Map the creators address to total number of votes received
        creator_total_votes: Map<ContractAddress, u256>,
        /// - Map the poll_id to the total number of votes

        /// - Map the poll_id and the voter address to the total number of votes by each voter
        voter_vote_count: Map<ContractAddress, u256>,
        /// - Map poll_id to the address of the voters
        poll_voters: Map<u256, ContractAddress>,
        /// # implemented this storage slot because the Poll struct does not Implement Array<T> Or
        /// Span<T>
        /// - Map the poll_id --> option_index --> the text content
        poll_options: Map<(u256, usize), ByteArray>,
        /// - Map the poll_id --> the option --> total vote on each option Global counters
        poll_option_votes: Map<(u256, u32), u256>,
        /// # Global conter state
        /// - Next_id of new poll
        next_poll_id: u256,
        /// - Total number of polls created
        total_polls_count: u256,
        /// - Total number of active polls
        total_active_polls: u256,
        ///
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }


    // All event to emit when action happens
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        /// create poll event
        PollCreated: PollCreated,
        // cast vote event
        VoteCasted: VoteCasted,
        /// end vote event
        PollEnded: PollEnded,
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
        self.next_poll_id.write(1);
        self.total_polls_count.write(0);
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
            assert(title.len() > 0, 'Title required');
            assert(title.len() <= 15, 'Title too long');
            assert(description.len() > 0, 'Description required');
            assert(description.len() > 20, 'Description required');

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
                    assert(time > current_time, 'end time must be in future');
                    Option::Some(time)
                },
                Option::None => Option::None(()),
            };

            // get the global next_poll_id
            let poll_id = self.next_poll_id.read();

            /// process the token gating configuration
            /// if token_gate_config.is_some()
            /// then validate the configuration
            /// else set default values
            let TokenGateConfig {
                enabled: is_token_gated, gate_type, token_address, minimum_balance, required_nft_id,
            } = process_and_validate_token_gate_config(creator, token_gate_config);

            // create a new poll instance
            let poll = Poll {
                poll_id: poll_id,
                creator: creator,
                title: title.clone(),
                description: description,
                poll_type: poll_type,
                created_at: get_block_timestamp(),
                end_time: final_end_time,
                is_active: true,
                total_votes: 0,
                num_options: poll_options.len(),
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
            self.total_polls_count.write(self.total_polls_count.read() + 1);
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

            /// allow only if the voter is not the pool creator
            assert(poll.creator != voter, 'Poll creator cannot vote');

            /// allow voting only if the poll exist
            assert(poll.poll_id == poll_id, 'Poll does not exist');

            /// allow to vote only if the poll is still active
            assert(self.active_polls.read(poll_id), 'Poll is not active');

            /// allow to vote only if not voted before
            assert(!self.user_has_voted.read((poll_id, voter)), 'Already voted');

            /// allow only if the end_time is Option::None
            if let Some(time) = poll.end_time {
                let current_time = get_block_timestamp();
                assert(current_time < time, 'poll has ended');
            }

            /// Validate if the poll is token-gated
            if poll.is_token_gated {
                validate_voter_eligibility(voter, poll.clone());
            }

            /// # Read storage slots

            /// - Read the poll option votes
            let options_count = self.poll_option_votes.read((poll_id, option_index.into()));

            /// - Read the creator total votes
            let creator_total_votes = self.creator_total_votes.read(poll.creator);

            /// - Read the voter vote count
            let voter_vote_count = self.voter_vote_count.read(voter);

            /// # Write storage slots

            /// - Write the poll option votes
            self.poll_option_votes.write((poll_id, option_index.into()), options_count + 1);

            /// - Write the voter vote count
            self.voter_vote_count.write(voter, voter_vote_count + 1);

            /// - Write the creator total votes
            self.creator_total_votes.write(poll.creator, creator_total_votes + 1);

            /// - Write the poll voters
            self.poll_voters.write(poll_id, voter);

            /// Update and store the poll
            let updated_poll = Poll { total_votes: poll.total_votes + 1, ..poll };
            self.polls.write(poll_id, updated_poll);

            // Create vote instance
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
        fn close_poll(ref self: ContractState, poll_id: u256) {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            /// Read the poll
            let mut poll = self.polls.read(poll_id);
            /// call the poll creator

            let is_creator = poll.creator;

            /// allow only if the input poll_id and poll.poll_id  matches
            assert(poll.poll_id == poll_id, 'Poll does not exist');

            /// allow only if the caller is the creator
            assert(is_creator == caller, 'Only creator can close poll');

            assert(poll.is_active, 'Poll already closed');

            if poll.end_time.unwrap() > 0 {
                assert(current_time >= poll.end_time.unwrap(), 'Poll has not ended');
            }

            // Close poll
            poll.is_active = false;
            self.polls.write(poll_id, poll);
            self.active_polls.write(poll_id, false);
            self.total_active_polls.write(self.total_active_polls.read() - 1);

            // Emit event
            self
                .emit(
                    Event::PollEnded(
                        PollEnded {
                            poll_id: poll_id,
                            total_votes: self.polls.read(poll_id).total_votes,
                            winning_option: self.calculate_winner(poll_id).option_index,
                            ended_at: current_time,
                        },
                    ),
                );
        }


        /// # Read functions

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

        /// Get all active poll
        /// # Parameters
        /// - `poll_id`: The identifier of the poll
        ///
        /// # Returns
        /// - A boolean indicating whether the poll is active
        fn get_active_poll(self: @ContractState, poll_id: u256) -> bool {
            self.active_polls.read(poll_id)
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
        fn get_polls_by_creator(
            self: @ContractState, creator: ContractAddress, page: u256, page_size: u256,
        ) -> Array<Poll> {
            let mut creator_polls = ArrayTrait::new();
            let count = self.creator_poll_count.read(creator);
            let start = page * page_size + 1;
            let end = min(start + page_size - 1, count);

            let mut index = start;
            while index != end {
                let poll_id = self.polls_by_creator.read((creator, index));
                let poll = self.polls.read(poll_id);
                creator_polls.append(poll);
                index += 1;
            }

            creator_polls
        }
        /// Get total polls count
        fn get_total_polls(self: @ContractState) -> u256 {
            self.total_polls_count.read()
        }

        /// Get total vote per poll
        ///
        /// # Parameters
        /// - `poll_id`: The identifier of the poll
        fn get_poll_total_votes(self: @ContractState, poll_id: u256) -> u64 {
            self.polls.read(poll_id).total_votes
        }

        /// Get total vote per poll_option
        ///
        /// # Parameters
        /// - `poll_id`: The identifier of the poll
        /// - `option_index`: The index of the poll option
        ///
        /// # Return the total vote per option
        fn get_total_votes_per_poll_option(
            self: @ContractState, poll_id: u256, option_index: u8,
        ) -> u256 {
            self.poll_option_votes.read((poll_id, option_index.into()))
        }

        /// Get creator total votes count
        ///
        /// # Parameters
        /// - `creator`: The address of the poll creator
        ///
        /// # Returns
        /// - The total votes count for the specified creator
        fn get_creator_total_votes(self: @ContractState, creator: ContractAddress) -> u256 {
            self.creator_total_votes.read(creator)
        }

        /// Get poll_voters
        ///
        /// # Parameter
        /// - `poll_id` the poll identifier
        ///
        /// # Behaviour
        /// - Retrieves the addresses of all voters who participated in the specified poll
        ///
        /// # Returns
        /// - An array of `ContractAddress` representing the voters
        fn get_poll_voters(self: @ContractState, poll_id: u256) -> Array<ContractAddress> {
            let mut voters_address = ArrayTrait::new();
            let voters_count = self.polls.read(poll_id).total_votes;

            for _ in 1..=voters_count {
                let voter = self.poll_voters.read(poll_id);
                voters_address.append(voter);
            }
            voters_address
        }


        /// Calculate the winning option for a poll
        ///
        /// # Parameters
        /// - `poll_id`: The identifier of the poll
        ///
        /// # Behaviour
        /// - Iterates through the options of the specified poll to determine the option with the
        /// highest vote count
        ///
        /// # Returns
        fn calculate_winner(self: @ContractState, poll_id: u256) -> Winner {
            let poll = self.polls.read(poll_id);
            assert(poll.poll_id == poll_id, 'Poll does not exist');
            assert(!poll.is_active, 'Poll is still open');

            let mut max_votes: u256 = 0;
            let mut winner: u32 = 0;

            let num_options = poll.num_options;

            let mut i = 0;
            while i != num_options {
                let votes = self.poll_option_votes.read((poll_id, i));
                if votes > max_votes {
                    max_votes = votes;
                    winner = i;
                }
                i += 1;
            }

            Winner { option_index: winner, vote_count: max_votes }
        }


        /// Get poll results
        ///
        /// # Parameters
        /// - `poll_id`: The identifier of the poll
        ///
        /// # Behaviour
        /// - Calculates the total votes and percentage for each option in the specified poll
        ///
        /// # Returns
        /// - An array of `Result` structs containing the option index, vote count, and
        fn get_poll_results(self: @ContractState, poll_id: u256) -> Array<PollResult> {
            let mut results = ArrayTrait::new();
            let poll = self.polls.read(poll_id);
            assert(poll.poll_id == poll_id, 'Poll does not exist');

            let total_votes: u256 = poll.total_votes.try_into().unwrap();
            let num_options = poll.num_options;

            let mut i: u32 = 0;

            while i != num_options {
                let votes = self.poll_option_votes.read((poll_id, i));

                let percentage: u256 = if total_votes == 0 {
                    0
                } else {
                    (votes * 100_u256) / total_votes
                };

                let result = PollResult { option_index: i, votes: votes, percentage: percentage };
                results.append(result);

                i += 1;
            }
            results
        }

        fn get_voter_poll_count(
            self: @ContractState, poll_id: u256, voter: ContractAddress,
        ) -> u256 {
            self.voter_vote_count.read(voter)
        }


        fn get_voter_polls(
            self: @ContractState, voter: ContractAddress, page: u256, page_size: u256,
        ) -> Array<Poll> {
            let mut voter_polls = ArrayTrait::new();
            let count = self.voter_vote_count.read(voter);

            let start = page * page_size + 1;
            let end = min(start + page_size - 1, count);

            let mut index = start;
            while index != end {
                let poll_id = self.polls_by_creator.read((voter, index));
                let poll = self.polls.read(poll_id);
                voter_polls.append(poll);
                index += 1;
            }

            voter_polls
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();

            // Replace the class hash upgrading the contract
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
