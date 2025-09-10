use starknet::ContractAddress;
use crate::enums::poll_contract_enums::GateType;


/// Attendance session information
#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct AttendanceSession {
    pub session_id: u256,
    pub organizer: ContractAddress,
    pub title: ByteArray,
    pub description: ByteArray,
    pub location: ByteArray,
    pub is_active: bool,
    pub created_at: u64,
    pub end_time: Option<u64>,
    pub total_attendees: u256,
    /// Configuration for token gating
    pub is_token_gated: bool,
    pub gate_type: GateType,
    pub token_address: ContractAddress,
    pub minimum_balance: u32,
    pub required_nft_id: Option<u256>,
}

/// Individual attendance record
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct AttendanceRecord {
    pub attendee: ContractAddress,
    pub session_id: u256,
    pub checked_in_at: u64,
}
