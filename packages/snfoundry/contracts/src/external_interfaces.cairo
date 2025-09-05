use starknet::ContractAddress;


/// Interface for ERC20 token interactions
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}


/// Interface for ERC721(NFT) token interactions
#[starknet::interface]
pub trait IERC721<TContractState> {
    fn balance_of(self: @TContractState, owner: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
}

/// Interface for custom validation
#[starknet::interface]
pub trait ICustomValidator<TContractState> {
    fn can_participate(
        self: @TContractState, user: ContractAddress, poll_id: u256, custom_data: ByteArray,
    ) -> bool;
}
