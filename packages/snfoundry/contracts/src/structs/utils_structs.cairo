use starknet::ContractAddress;
use crate::enums::poll_contract_enums::GateType;

/// Token gate configuration struct
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct TokenGateConfig {
    pub enabled: bool,
    pub gate_type: GateType,
    pub token_address: ContractAddress,
    pub minimum_balance: u32,
    pub required_nft_id: Option<u256>,
}
