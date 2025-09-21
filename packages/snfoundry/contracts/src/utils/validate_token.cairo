use starknet::ContractAddress;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use core::num::traits::Pow;


pub fn strk_to_fri(token_address: ContractAddress, mut amount: u256) -> u256 {
  let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let decimals = token_dispatcher.decimals();
    
    let multiplier: u256 = 10.pow(decimals.into());
    amount * multiplier
}

