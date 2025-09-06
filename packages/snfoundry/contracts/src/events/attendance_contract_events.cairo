use starknet::ContractAddress;

/// Events
#[derive(Drop, starknet::Event)]
pub struct SessionCreated {
    #[key]
    pub session_id: u256,
    #[key]
    pub organizer: ContractAddress,
    pub title: ByteArray,
    pub created_at: u64,
}

#[derive(Drop, starknet::Event)]
pub struct CheckedIn {
    #[key]
    pub session_id: u256,
    #[key]
    pub attendee: ContractAddress,
    pub timestamp: u64,
}

// #[derive(Drop, starknet::Event)]
// pub struct CheckedOut {
//     pub session_id: u256,
//     pub attendee: ContractAddress,
//     pub timestamp: u64,
// }

#[derive(Drop, starknet::Event)]
pub struct SessionClosed {
    #[key]
    pub session_id: u256,
    #[key]
    pub closed_by: ContractAddress,
    pub timestamp: u64,
}
