/// Attendance contract interface
/// Defines the functions for managing attendance sessions and records
/// including creation, check-in, and retrieval of session and attendance data.

use starknet::ContractAddress;
use crate::structs::attendance_contract_structs::{AttendanceRecord, AttendanceSession};
use crate::structs::utils_structs::TokenGateConfig;


#[starknet::interface]
pub trait IAttendanceContract<TContractState> {
    /// Create a new attendance session
    fn create_session(
        ref self: TContractState,
        title: ByteArray,
        description: ByteArray,
        location: ByteArray,
        end_time: Option<u64>,
        token_gate_config: Option<TokenGateConfig>,
    ) -> u256;

    /// Check in to a session
    fn check_in(ref self: TContractState, session_id: u256);


    // /// Close a session (organizer only)
    fn close_session(ref self: TContractState, session_id: u256);

    /// Get session information
    fn get_session(self: @TContractState, session_id: u256) -> AttendanceSession;

    /// Get attendance record for a user
    fn get_attendance_record(
        self: @TContractState, session_id: u256, attendee: ContractAddress,
    ) -> AttendanceRecord;

    /// Check if user is currently checked in
    fn is_checked_in(self: @TContractState, session_id: u256, attendee: ContractAddress) -> bool;

    /// Get all attendees for a session
    fn get_attendees(
        self: @TContractState, session_id: u256, page: u256, page_size: u256,
    ) -> Array<AttendanceRecord>;

    /// Get active sessions
    fn get_active_sessions(self: @TContractState, session_id: u256) -> bool;

    /// Get sessions created by organizer
    fn get_sessions_by_organizer(
        self: @TContractState, organizer: ContractAddress, page: u256, page_size: u256,
    ) -> Array<u256>;

    /// Get user's attendance history
    fn get_user_attendance_history(self: @TContractState, user: ContractAddress, page: u256, page_size: u256,) -> Array<AttendanceSession>;

    /// Get total sessions count
    fn get_total_sessions(self: @TContractState) -> u256;

    /// Check if session has capacity
    // fn has_capacity(self: @TContractState, session_id: u256) -> bool;
}
