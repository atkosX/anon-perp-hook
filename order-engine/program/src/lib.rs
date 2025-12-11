// SP1 ZK Proof Program for Order Validation
// Validates perp order commitments and generates proofs without revealing sensitive data

#![no_std]

use sp1_zkvm::prelude::*;
use sha2::{Sha256, Digest};

/// Order commitment structure
#[derive(Debug, Clone)]
struct OrderCommitment {
    commitment: [u8; 32],      // Hash of order data
    nullifier: [u8; 32],      // Prevents double-spending
    balance_hash: [u8; 32],   // Hash of user balance
}

/// Order validation result
#[derive(Debug, Clone)]
struct ValidationResult {
    is_valid: bool,
    commitment_valid: bool,
    balance_sufficient: bool,
    nullifier_unused: bool,
}

/// Main entry point for SP1 program
/// Validates perp order commitments and generates proofs
#[sp1_main]
fn main() {
    // Read public values from host (order commitment, nullifier, balance proof)
    let order_commitment = env::read::<OrderCommitment>();
    
    // Read private values (actual order data, user balance, nullifier set)
    let order_data = env::read::<Vec<u8>>();
    let user_balance = env::read::<u64>();
    let required_margin = env::read::<u64>();
    let nullifier_set = env::read::<Vec<[u8; 32]>>();
    
    // Validate order commitment
    let commitment_valid = validate_commitment(&order_data, &order_commitment.commitment);
    
    // Check balance sufficiency (without revealing actual balance)
    let balance_sufficient = user_balance >= required_margin;
    let balance_hash = hash_balance(user_balance);
    
    // Check nullifier hasn't been used
    let nullifier_unused = !nullifier_set.contains(&order_commitment.nullifier);
    
    // Overall validation result
    let is_valid = commitment_valid && balance_sufficient && nullifier_unused;
    
    // Create validation result
    let result = ValidationResult {
        is_valid,
        commitment_valid,
        balance_sufficient,
        nullifier_unused,
    };
    
    // Commit public results (proof that validation passed without revealing private data)
    env::commit(&order_commitment.commitment);
    env::commit(&order_commitment.nullifier);
    env::commit(&balance_hash);
    env::commit(&result);
}

/// Validate that order data matches the commitment
fn validate_commitment(order_data: &[u8], commitment: &[u8; 32]) -> bool {
    // Hash the order data
    let computed_hash = hash_data(order_data);
    
    // Compare with commitment
    computed_hash == *commitment
}

/// Hash order data to create commitment using SHA256
fn hash_data(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().into()
}

/// Hash balance for proof (without revealing actual balance) using SHA256
fn hash_balance(balance: u64) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(balance.to_le_bytes());
    hasher.finalize().into()
}

