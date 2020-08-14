address 0x0 {
  module ValidatorUniverse {
    ///////////////////////////////////////////////////////////////////////////
    // OpenLibra Module
    // ValidatorUniverse - stores all the validators who submitted a vdf proof.
    // File Prefix for errors: 2201
    ///////////////////////////////////////////////////////////////////////////

    use 0x0::Vector;
    use 0x0::Transaction;
    use 0x0::Signer;
    use 0x0::FixedPoint32;
    use 0x0::Stats;
    use 0x0::Option;

    struct ValidatorEpochInfo {
        validator_address: address,
        weight: u64
    }

    // resource for tracking the universe of accounts that have submitted a mined proof correctly, with the epoch number.
    resource struct ValidatorUniverse {
        validators: vector<ValidatorEpochInfo>
    }

    // function to initialize ValidatorUniverse in genesis.
    // This is triggered in new epoch by Configuration in Genesis.move
    // Function code: 01 Prefix: 220101
    public fun initialize(account: &signer){
      // Check for transactions sender is association
      let sender = Signer::address_of(account);
      Transaction::assert(sender == 0x0, 220101014010);

      move_to<ValidatorUniverse>(account, ValidatorUniverse {
          validators: Vector::empty<ValidatorEpochInfo>()
      });
    }

    // This function is called to add validator to the validator universe.
    // Function code: 02 Prefix: 220102
    public fun add_validator(addr: address) acquires ValidatorUniverse {
      let collection = borrow_global_mut<ValidatorUniverse>(0x0);
      if(!validator_exists_in_universe(collection, addr))
      Vector::push_back<ValidatorEpochInfo>(
        &mut collection.validators,
        ValidatorEpochInfo{
        validator_address: addr,
        weight: 1
      });
    }

    // OL A simple public function to query the EligibleValidators.
    // Only system addresses should be able to access this function
    // Eligible validators are all those nodes who have mined a VDF proof at any time.
    // TODO (nelaturuk): Wonder if this helper is necessary since it is just stripping the Validator Universe vector of other fields.
    // Function code: 03 Prefix: 220103
    public fun get_eligible_validators(account: &signer) : vector<address> acquires ValidatorUniverse {
      let sender = Signer::address_of(account);
      Transaction::assert(sender == 0x0, 220101014010);

      let eligible_validators = Vector::empty<address>();
      // Create a vector with all eligible validator addresses
      // Get all the data from the ValidatorUniverse resource stored in the association/system address.
      let collection = borrow_global<ValidatorUniverse>(0x0);

      let i = 0;
      let validator_list = &collection.validators;
      let len = Vector::length<ValidatorEpochInfo>(validator_list);

      while (i < len) {
          Vector::push_back(&mut eligible_validators, Vector::borrow<ValidatorEpochInfo>(validator_list, i).validator_address);
          i = i + 1;
      };

      eligible_validators
    }

    // Simple convenience function to lookup if a validator exists in ValidatorUniverse structure.
    // Function code: 04 Prefix: 220104
    fun validator_exists_in_universe(validatorUniverse: &ValidatorUniverse, addr: address): bool {
      let i = 0;
      let validator_list = &validatorUniverse.validators;
      let len = Vector::length<ValidatorEpochInfo>(validator_list);
      while (i < len) {
          if (Vector::borrow<ValidatorEpochInfo>(validator_list, i).validator_address == addr) return true;
          i = i + 1;
      };
      false
    }

    // This function is the Proof of Weight. This is what calculates the values
    // for the consensus vote power, which will be used by Reconfiguration to call LibraSystem::bulk_update_validators.
    // Function code: 05 Prefix: 220105
    public fun proof_of_weight(addr: address, is_validator_in_current_epoch: bool): u64 acquires ValidatorUniverse {
      let sender = Transaction::sender();
      Transaction::assert(sender == 0x0, 22010105014010);

      //1. borrow the Validator's ValidatorEpochInfo
      // Get the validator
      let collection =  borrow_global_mut<ValidatorUniverse>(0x0);

      // Getting index of the validator
      let index_vec = get_validator_index_(&collection.validators, addr);
      Transaction::assert(Option::is_some(&index_vec), 220105022040);
      let index = *Option::borrow(&index_vec);

      let validator_list = &mut collection.validators;
      let validatorInfo = Vector::borrow_mut<ValidatorEpochInfo>(validator_list, index);


      // Weight is metric based on: The number of epochs the miners have been mining for
      let weight = 1;

      // If the validator mined in current epoch, increment it's weight.
      if(is_validator_in_current_epoch)
        weight = validatorInfo.weight + 1;

      validatorInfo.weight = weight;
      weight
    }

    // Get the index of the validator by address in the `validators` vector
    fun get_validator_index_(validators: &vector<ValidatorEpochInfo>, addr: address): Option::T<u64>{
      let size = Vector::length(validators);

      let i = 0;
      while (i < size) {
          let validator_info_ref = Vector::borrow(validators, i);
          if (validator_info_ref.validator_address == addr) {
              return Option::some(i)
          };
          i = i + 1;
      };

      return Option::none()
    }

    // Get the validatorInfo by address in the `validators` vector
    fun get_validator(addr: address): ValidatorEpochInfo acquires ValidatorUniverse{

      let validators = &borrow_global_mut<ValidatorUniverse>(0x0).validators;
      let size = Vector::length(validators);

      let i = 0;
      while (i < size) {
          let validator_info_ref = Vector::borrow(validators, i);
          if (validator_info_ref.validator_address == addr) {
              return *validator_info_ref
          };
          i = i + 1;
      };

      return ValidatorEpochInfo{
        validator_address: {{0x0}},
        weight: 0
      }
    }

    // Check the liveness of the validator in the previous epoch
    // Function code: 07 Prefix: 220107
    public fun check_if_active_validator(addr: address, epoch_length: u64, current_block_height: u64): bool {
      // Calculate start and end block height for the current epoch
      // What about empty blocks that get created after every epoch?

      let end_block_height = current_block_height;
      let epoch_count = epoch_length - 2;  // Not all blocks are committed at current block height.

      // The current block_height needs to be at least the length of one (the first) epoch.
      Transaction::assert(end_block_height >= epoch_count, 220107015120);

      let start_block_height = end_block_height - epoch_count;

      // Calculating liveness threshold which is signing 66% of the blocks in epoch.
      // Note that nodes in hotstuff stops voting after 2/3 consensus has been reached, and skip to next block.

      let threshold_signing = FixedPoint32::divide_u64(66, FixedPoint32::create_from_rational(100, 1)) * epoch_count;

      let active_validator = Stats::node_heuristics(addr, start_block_height, end_block_height);

      if (active_validator < threshold_signing) {
          return false
      };

      true
    }

    // Function code: 06 Prefix: 220106
    public fun get_validator_weight(addr: address): u64 acquires ValidatorUniverse{
      let sender = Transaction::sender();
      Transaction::assert(sender == 0x0, 220106014010);

      let validatorInfo = get_validator(addr);

      // Validator not in universe error
      Transaction::assert(validatorInfo.validator_address != 0x0, 220106022040);
      return validatorInfo.weight
    }
  }
}