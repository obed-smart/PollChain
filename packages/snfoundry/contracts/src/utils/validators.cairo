use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use starknet::ContractAddress;
use crate::enums::poll_contract_enums::GateType;
use crate::structs::poll_contract_structs::Poll;
use crate::structs::utils_structs::TokenGateConfig;


pub fn process_and_validate_token_gate_config(
    creator: ContractAddress, config: Option<TokenGateConfig>,
) -> TokenGateConfig {
    match config {
        Option::Some(mut cfg) => {
            if !cfg.enabled {
                return TokenGateConfig {
                    enabled: false,
                    gate_type: GateType::None,
                    token_address: Zero::zero(),
                    minimum_balance: 0,
                    required_nft_id: Option::None,
                };
            }

            match cfg.gate_type {
                GateType::ERC20Token => {
                    assert(!cfg.token_address.is_zero(), 'Token address cannot be zero');
                    if cfg.minimum_balance == 0 {
                        cfg.minimum_balance = 1;
                    }

                    let token_contract = IERC20Dispatcher { contract_address: cfg.token_address };
                    let balance = token_contract.balance_of(creator);
                    assert(balance >= cfg.minimum_balance.into(), 'Creator lacks required tokens');
                },
                GateType::ERC721NFT => {
                    assert(!cfg.token_address.is_zero(), 'NFT address cannot be zero');

                    let nft_contract = IERC721Dispatcher { contract_address: cfg.token_address };
                    match cfg.required_nft_id {
                        Option::Some(required_id) => {
                            let owner = nft_contract.owner_of(required_id);
                            assert(owner == creator, 'Creator lacks required NFT');
                        },
                        Option::None => {
                            if cfg.minimum_balance == 0 {
                                cfg.minimum_balance = 1;
                            }
                            let balance = nft_contract.balance_of(creator);
                            assert(
                                balance >= cfg.minimum_balance.into(),
                                'Creator lacks required NFTs',
                            );
                        },
                    }
                },
                GateType::ERC721NFTCollection => {
                    assert(!cfg.token_address.is_zero(), 'NFT address cannot be zero');
                    if cfg.minimum_balance == 0 {
                        cfg.minimum_balance = 1;
                    }

                    let nft_contract = IERC721Dispatcher { contract_address: cfg.token_address };
                    let balance = nft_contract.balance_of(creator);
                    assert(balance >= cfg.minimum_balance.into(), 'Missing required NFTs');
                },
                GateType::None => { cfg.enabled = false; },
            }

            cfg
        },
        Option::None => {
            TokenGateConfig {
                enabled: false,
                gate_type: GateType::None,
                token_address: Zero::zero(),
                minimum_balance: 0,
                required_nft_id: Option::None,
            }
        },
    }
}


pub fn validate_voter_eligibility(voter: ContractAddress, poll: Poll) {
    if !poll.is_token_gated {
        return;
    }

    match poll.gate_type {
        GateType::ERC20Token => {
            let token_contract = IERC20Dispatcher { contract_address: poll.token_address };
            let balance = token_contract.balance_of(voter);
            assert(balance >= poll.minimum_balance.into(), 'Not enough tokens');
        },
        GateType::ERC721NFT => {
            let nft_contract = IERC721Dispatcher { contract_address: poll.token_address };

            if let Option::Some(id) = poll.required_nft_id {
                let owner = nft_contract.owner_of(id);
                assert(owner == voter, 'NFT required to vote');
            } else {
                let balance = nft_contract.balance_of(voter);
                assert(balance >= poll.minimum_balance.into(), 'Must own NFT');
            }
        },
        GateType::ERC721NFTCollection => {
            let nft_contract = IERC721Dispatcher { contract_address: poll.token_address };
            let balance = nft_contract.balance_of(voter);
            assert(balance >= poll.minimum_balance.into(), 'Must own NFT from collection');
        },
        GateType::None => {},
    }
}

