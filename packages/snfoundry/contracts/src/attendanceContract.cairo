#[starknet::contract]
pub mod AttendanceContract {
    use core::cmp::min;
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::events::attendance_contract_events::{CheckedIn, SessionClosed, SessionCreated};
    use crate::interfaces::iattendance_contract_interface::IAttendanceContract;
    use crate::structs::attendance_contract_structs::*;
    use crate::structs::utils_structs::TokenGateConfig;
    use crate::utils::validators::process_and_validate_token_gate_config;


    #[storage]
    struct Storage {
        /// Core session data

        // session_id -> AttendanceSession
        sessions: Map<u256, AttendanceSession>,
        // (session_id, attendee) -> AttendanceRecord
        attendance_records: Map<(u256, ContractAddress), AttendanceRecord>,
        // (session_id, attendee) -> is_checked_in
        is_checked_in: Map<(u256, ContractAddress), bool>,
        /// session management
        /// - session_id -> is_active
        active_sessions: Map<u256, bool>,
        /// - (organizer, index) -> session_id
        sessions_by_organizer: Map<(ContractAddress, u256), u256>,
        /// - organizer -> number of sessions organized
        organizer_session_count: Map<ContractAddress, u256>,
        /// Attendee tracking
        /// - (session_id, index) -> attendee
        session_attendees: Map<(u256, u256), ContractAddress>,
        // - (attendee , index) -> session_id
        user_sessions: Map<(ContractAddress, u256), u256>,
        /// - session_id -> total number of attendees
        user_session_count: Map<ContractAddress, u256>,
        /// Global Counters
        next_session_id: u256,
        total_sessions: u256,
        total_active_sessions: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SessionCreated: SessionCreated,
        CheckedIn: CheckedIn,
        SessionClosed: SessionClosed,
    }

    impl AttendanceImpl of IAttendanceContract<ContractState> {
        fn create_session(
            ref self: ContractState,
            title: ByteArray,
            description: ByteArray,
            location: ByteArray,
            end_time: Option<u64>,
            token_gate_config: Option<TokenGateConfig>,
        ) -> u256 {
            let organizer = get_caller_address();
            let session_id = self.next_session_id.read();
            let timestamp = get_block_timestamp();

            // Basic validations
            assert(!organizer.is_zero(), 'Invalid organizer address');
            assert(title.len() > 0, 'Title required');
            assert(title.len() <= 15, 'Title too long');
            assert(description.len() > 0, 'Description required');
            assert(description.len() > 10, 'Description required');

            // Validate end_time if provided
            // validate the endtime to know if it Present or Not --> Option<T>
            let final_end_time = match end_time {
                Option::Some(time) => {
                    let current_time = get_block_timestamp();
                    assert(time > current_time, 'end time must be in future');
                    Option::Some(time)
                },
                Option::None => Option::None(()),
            };

            // Process and validate token gate config
            let TokenGateConfig {
                enabled: is_token_gated, gate_type, token_address, minimum_balance, required_nft_id,
            } = process_and_validate_token_gate_config(organizer, token_gate_config);

            // session instance
            let session = AttendanceSession {
                session_id: session_id,
                organizer: organizer,
                title: title.clone(),
                description: description,
                location: location,
                is_active: true,
                created_at: timestamp,
                end_time: final_end_time,
                total_attendees: 0,
                is_token_gated: is_token_gated,
                gate_type: gate_type,
                token_address: token_address,
                minimum_balance: minimum_balance,
                required_nft_id: required_nft_id,
            };

            // Store session
            self.sessions.write(session_id, session);
            self.active_sessions.write(session_id, true);

            // organizer session tracking
            let organizer_count = self.organizer_session_count.read(organizer);
            self.organizer_session_count.write(organizer, organizer_count + 1);
            self.sessions_by_organizer.write((organizer, organizer_count), session_id);

            // Update global counters
            self.next_session_id.write(session_id + 1);
            self.total_sessions.write(self.total_sessions.read() + 1);
            self.total_active_sessions.write(self.total_active_sessions.read() + 1);

            self
                .emit(
                    Event::SessionCreated(
                        SessionCreated {
                            session_id: session_id,
                            organizer: organizer,
                            title: title,
                            created_at: timestamp,
                        },
                    ),
                );

            session_id
        }

        /// Check in to a session
        fn check_in(ref self: ContractState, session_id: u256) {
            let attendee = get_caller_address();
            let current_time = get_block_timestamp();

            // Check if already checked in
            assert(!attendee.is_zero(), 'Invalid attendee address');
            assert(!self.is_checked_in(session_id, attendee), 'Already checked in');

            // Get session
            let mut session = self.sessions.read(session_id);
            assert(session.session_id == session_id, 'Session not found');
            assert(session.is_active, 'Session is not active');

            if let Some(time) = session.end_time {
                assert(current_time <= time, 'Session has ended');
            }

            if session.is_token_gated {
            }

            let attendance_record = AttendanceRecord {
                attendee: attendee, session_id: session_id, checked_in_at: current_time,
            };

            // Store attendance record
            self.attendance_records.write((session_id, attendee), attendance_record);
            self.is_checked_in.write((session_id, attendee), true);

            let attendee_count = session.total_attendees;
            self.session_attendees.write((session_id, attendee_count), attendee);
            self.user_sessions.write((attendee, attendee_count), session_id);
            self.user_session_count.write(attendee, attendee_count + 1);

            session.total_attendees += 1;
            self.sessions.write(session_id, session);

            self
                .emit(
                    Event::CheckedIn(
                        CheckedIn {
                            session_id: session_id, attendee: attendee, timestamp: current_time,
                        },
                    ),
                );
        }


        /// Close a session (organizer only)
        fn close_session(ref self: ContractState, session_id: u256) {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Invalid caller address');

            let mut session = self.sessions.read(session_id);
            let current_time = get_block_timestamp();

            assert(session.session_id == session_id, 'Session not found');
            assert(session.is_active, 'Session already closed');
            assert(session.organizer == caller, 'Only organizer');

            // If end_time is set, ensure current time is past end_time
            if let Some(time) = session.end_time {
                assert(time >= current_time, 'Session not yet ended');
            }

            // Close session
            session.is_active = false;
            self.sessions.write(session_id, session);
            self.active_sessions.write(session_id, false);
            self.total_active_sessions.write(self.total_active_sessions.read() - 1);

            // Emit event
            self
                .emit(
                    Event::SessionClosed(
                        SessionClosed {
                            session_id: session_id, closed_by: caller, timestamp: current_time,
                        },
                    ),
                );
        }

        /// Get session information
        fn get_session(self: @ContractState, session_id: u256) -> AttendanceSession {
            self.sessions.read(session_id)
        }

        /// Get attendance record for a user
        fn get_attendance_record(
            self: @ContractState, session_id: u256, attendee: ContractAddress,
        ) -> AttendanceRecord {
            self.attendance_records.read((session_id, attendee))
        }

        /// Check if user is currently checked in
        fn is_checked_in(
            self: @ContractState, session_id: u256, attendee: ContractAddress,
        ) -> bool {
            self.is_checked_in.read((session_id, attendee))
        }

        /// Get all attendees for a session
        fn get_attendees(
            self: @ContractState, session_id: u256, page: u256, page_size: u256,
        ) -> Array<AttendanceRecord> {
            let mut attendees = ArrayTrait::new();
            let session = self.sessions.read(session_id);
            let total_attendees = session.total_attendees;
            let start = page * page_size + 1;
            let end = min(start + page_size - 1, total_attendees);

            let mut index = start;

            while index != end {
                let attendee = self.session_attendees.read((session_id, index));
                let attendee_record = self.attendance_records.read((session_id, attendee));
                attendees.append(attendee_record);
                index += 1;
            }

            attendees
        }

        /// Get active sessions
        fn get_active_sessions(self: @ContractState, session_id: u256) -> bool {
            self.active_sessions.read(session_id)
        }

        /// Get sessions created by organizer
        fn get_sessions_by_organizer(
            self: @ContractState, organizer: ContractAddress, page: u256, page_size: u256,
        ) -> Array<u256> {
            let mut sessions_by_organizer = ArrayTrait::new();
            let total_sessions = self.organizer_session_count.read(organizer);

            let start = page * page_size + 1;
            let end = min(start + page_size - 1, total_sessions);

            let mut index = start;

            while index != end {
                let session_id = self.sessions_by_organizer.read((organizer, index));
                sessions_by_organizer.append(session_id);
                index += 1;
            }
            sessions_by_organizer
        }

        /// Get user's attendance history
        fn get_user_attendance_history(
            self: @ContractState, user: ContractAddress, page: u256, page_size: u256,
        ) -> Array<AttendanceSession> {
            let mut attendance_history = ArrayTrait::new();
            let total_sessions = self.user_session_count.read(user);

            let start = page * page_size + 1;
            let end = min(start + page_size - 1, total_sessions);

            let mut index = start;

            while index != end {
                let session_id = self.user_sessions.read((user, index));
                let session = self.sessions.read(session_id);
                attendance_history.append(session);
                index += 1;
            }

            attendance_history
        }

        /// Get total sessions count
        fn get_total_sessions(self: @ContractState) -> u256 {
            self.total_sessions.read()
        }
        /// Check if session has capacity
    // fn has_capacity(self: @ContractState, session_id: u256) -> bool {
    // }
    }
}
