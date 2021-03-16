address 0x1{
  module AutoPay{
///////////////////////////////////////////////////////////////////////////
  // 0L Module
  // Auto Pay - 
  // File Prefix for errors: 0101
  ///////////////////////////////////////////////////////////////////////////
    use 0x1::Vector;
    use 0x1::Option::{Self,Option};
    use 0x1::Signer;
    use 0x1::LibraAccount;
    use 0x1::GAS::GAS;
    use 0x1::FixedPoint32;
    use 0x1::CoreAddresses;
    use 0x1::LibraConfig;
    use 0x1::LibraTimestamp;
    use 0x1::Epoch;
    use 0x1::Globals;
    use 0x1::Errors;

    /// Attempted to send funds to an account that does not exist
    const EPAYEE_DOES_NOT_EXIST: u64 = 17;
    /// Invalid payment type given
    const INVALID_PAYMENT_TYPE: u64 = 18;

    /// Maximum value for the Payment type selection
    const MAX_TYPE: u8 = 3;

    // types of Payments
    /// send percent of balance at end of epoch payment type
    const PERCENT_OF_BALANCE: u8 = 0;
    /// send percent of the change in balance since the last tick payment type
    const PERCENT_OF_CHANGE: u8 = 1;
    /// send a certain amount each tick until end_epoch is reached payment type
    const AMOUNT_UNTIL: u8 = 2;
    /// send a certain amount once at the next tick payment type
    const ONE_SHOT: u8 = 3;

    resource struct Tick {
      triggered: bool,
    }
    // List of payments. Each account will own their own copy of this struct
    resource struct Data {
      payments: vector<Payment>,
    }

    // One copy of this struct will be created. It will be stored in 0x0.
    // It keeps track of all accounts that have autopay enabled and updates the 
    // list as accounts change their Status structs

    // It also keeps track of the current epoch for efficiency (to prevent repeated
    // queries to LibraBlock)
    resource struct AccountList {
      accounts: vector<address>,
      current_epoch: u64,
    }

    // This is the structure of each Payment struct which represents one automatic
    // payment held by an account
    // Possible types:
    // 0: amt% of current balance until end epoch
    // 1: amt% of inflow until end_epoch 
    // 2: amt gas until end_epoch
    // 3: amt gas, one time payment
    struct Payment {
      // TODO: name should be a string to store a memo
      // name: u64,
      uid: u64,
      type: u8,
      payee: address,
      end_epoch: u64,  // end epoch is inclusive, must just be higher than current epoch for type 3
      prev_bal: u64, //only used for type 1
      amt: u64, //percentage for types 0 & 1, count for 2 & 3
    }

    ///////////////////////////////
    // Public functions only OxO //
    //////////////////////////////
    public fun tick(vm: &signer): bool acquires Tick {
      assert(Signer::address_of(vm) == CoreAddresses::LIBRA_ROOT_ADDRESS(), 0101014010);
      assert(exists<Tick>(CoreAddresses::LIBRA_ROOT_ADDRESS()), 0101024010);
      
      let tick_state = borrow_global_mut<Tick>(Signer::address_of(vm));

      if (!tick_state.triggered) {
        let timer = LibraTimestamp::now_seconds() - Epoch::get_timer_seconds_start(vm);
        let tick_interval = Globals::get_epoch_length();
        if (timer > tick_interval/2) {
          tick_state.triggered = true;
          return true
        }
      };
      false
    }

    public fun reconfig_reset_tick(vm: &signer) acquires Tick{
      let tick_state = borrow_global_mut<Tick>(Signer::address_of(vm));
      tick_state.triggered = false;
    }
    // Initialize the entire autopay module by creating an empty AccountList object
    // Called in Genesis
    // Function code 010101
    public fun initialize(sender: &signer) {
      assert(Signer::address_of(sender) == CoreAddresses::LIBRA_ROOT_ADDRESS(), 0101014010);
      move_to<AccountList>(sender, AccountList { accounts: Vector::empty<address>(), current_epoch: 0, });
      move_to<Tick>(sender, Tick {triggered: false})
    }

    // This is the main function for this module. It is called once every epoch
    // by 0x0::LibraBlock in the block_prologue function.
    // This function iterates through all autopay-enabled accounts and processes
    // any payments they have due in the current epoch from their list of payments.
    // Note: payments from epoch n are processed at the epoch_length/2
    // Function code 010106
    public fun process_autopay(
      vm: &signer,
    ) acquires AccountList, Data {
      // Only account 0x0 should be triggering this autopayment each block
      assert(Signer::address_of(vm) == CoreAddresses::LIBRA_ROOT_ADDRESS(), 0101064010);

      let epoch = LibraConfig::get_current_epoch();

      // Go through all accounts in AccountList
      // This is the list of accounts which currently have autopay enabled
      let account_list = &borrow_global<AccountList>(CoreAddresses::LIBRA_ROOT_ADDRESS()).accounts;
      let accounts_length = Vector::length<address>(account_list);
      let account_idx = 0;

      while (account_idx < accounts_length) {

        let account_addr = Vector::borrow<address>(account_list, account_idx);
        
        // Obtain the account balance
        let account_bal = LibraAccount::balance<GAS>(*account_addr);
        
        // Go through all payments for this account and pay 
        let payments = &mut borrow_global_mut<Data>(*account_addr).payments;
        let payments_len = Vector::length<Payment>(payments);
        let payments_idx = 0;
        
        while (payments_idx < payments_len) {
          let delete_payment = false;
          {
            let payment = Vector::borrow_mut<Payment>(payments, payments_idx);
            // If payment end epoch is greater, it's not an active payment anymore, so delete it
            if (payment.end_epoch >= epoch) {
              // A payment will happen now
              // Obtain the amount to pay 
              let amount = if (payment.type == PERCENT_OF_BALANCE) {
                FixedPoint32::multiply_u64(account_bal , FixedPoint32::create_from_rational(payment.amt, 100))
              } else if (payment.type == PERCENT_OF_CHANGE) {
                if (account_bal > payment.prev_bal) {
                  FixedPoint32::multiply_u64(account_bal - payment.prev_bal, FixedPoint32::create_from_rational(payment.amt, 100))
                } else {
                  // if account balance hasn't gone up, no value is transferred
                  0
                }
              } else {
                // in remaining cases, payment is simple amaount given, not a percentage
                payment.amt
              };
              
              if (amount != 0) {
                LibraAccount::make_payment<GAS>(*account_addr, payment.payee, amount, x"", x"", vm);
              };

              // update previous balance for next calculation
              payment.prev_bal = LibraAccount::balance<GAS>(*account_addr);

              // if it's a one shot payment, delete it once it has done its job
              if (payment.type == ONE_SHOT) {
                delete_payment = true;
              }
              
            } else {
              delete_payment = true;
            };
          };
          if (delete_payment == true) {
            Vector::remove<Payment>(payments, payments_idx);
            payments_len = payments_len - 1;
          }
          else {
            payments_idx = payments_idx + 1;
          };
        };
        account_idx = account_idx + 1;
      };
    }

    ////////////////////////////////////////////
    // Public functions only account owner    //
    // Enable, disable, create/delete instructions //
    ////////////////////////////////////////////

    // Each account needs to initialize autopay on it's account
    // Function code 010102
    public fun enable_autopay(acc: &signer) acquires AccountList{
      let addr = Signer::address_of(acc);
      // append to account list in system state 0x0
      let accounts = &mut borrow_global_mut<AccountList>(CoreAddresses::LIBRA_ROOT_ADDRESS()).accounts;
      if (!Vector::contains<address>(accounts, &addr)) {
        Vector::push_back<address>(accounts, addr);
      };
      // Initialize the instructions Data on user account state 
      move_to<Data>(acc, Data { payments: Vector::empty<Payment>()});
    }

    // An account can disable autopay on it's account
    // Function code 010103
    public fun disable_autopay(acc: &signer) acquires AccountList, Data {
      
      let addr = Signer::address_of(acc);

      // We destroy the data resource for sender
      let sender_data = move_from<Data>(addr);
      let Data { payments: _ } = sender_data;

      // pop that account from AccountList
      let accounts = &mut borrow_global_mut<AccountList>(CoreAddresses::LIBRA_ROOT_ADDRESS()).accounts;
      let (status, index) = Vector::index_of<address>(accounts, &addr);
      if (status) {
        Vector::remove<address>(accounts, index);
      }      
    }

    // Create a instruction from the sender's account
    // Function code 010104
    public fun create_instruction(
      sender: &signer, 
      uid: u64,
      type: u8,
      payee: address,
      end_epoch: u64,
      amt: u64
    ) acquires Data {
      let addr = Signer::address_of(sender);
      // Confirm that no payment exists with the same uid
      let index = find(addr, uid);
      if (Option::is_some<u64>(&index)) {
        // This is the case where the payment uid already exists in the vector
        assert(false, 010104011021);
      };
      let payments = &mut borrow_global_mut<Data>(addr).payments;

      assert(LibraAccount::exists_at(payee), Errors::not_published(EPAYEE_DOES_NOT_EXIST));

      assert(type <= MAX_TYPE, Errors::invalid_argument(INVALID_PAYMENT_TYPE));

      let account_bal = LibraAccount::balance<GAS>(addr);

      Vector::push_back<Payment>(payments, Payment {
        // name: name,
        uid: uid,
        type: type,
        payee: payee,
        end_epoch: end_epoch,
        prev_bal: account_bal,
        amt: amt,
      });
    }

    // Deletes the instruction with uid from the sender's account
    // Function code 010105
    public fun delete_instruction(account: &signer, uid: u64) acquires Data {
      let addr = Signer::address_of(account);
      let index = find(addr, uid);
      if (Option::is_none<u64>(&index)) {
        // Case when the payment to be deleted doesn't actually exist
        assert(false, 010105012040);
      };
      let payments = &mut borrow_global_mut<Data>(addr).payments;
      Vector::remove<Payment>(payments, Option::extract<u64>(&mut index));
    }

    ///////////////////////////////
    // Public functions to Query //
    // Can be queried by anyone  //
    //////////////////////////////

    // Any account can check to see if any of the accounts has autopay enabled
    // by checking in 0x0's AccountList
    public fun is_enabled(account: address): bool acquires AccountList {
      let accounts = &mut borrow_global_mut<AccountList>(CoreAddresses::LIBRA_ROOT_ADDRESS()).accounts;
      if (Vector::contains<address>(accounts, &account)) {
        return true
      };
      false
    }

    // Returns (sender address,  end_epoch, percentage)
    public fun query_instruction(account: address, uid: u64): (u8, address, u64, u64) acquires Data {
      // TODO: This can be made faster if Data.payments is stored as a BST sorted by 
      let index = find(account, uid);
      if (Option::is_none<u64>(&index)) {
        // Case where payment is not found
        return (0, 0x0, 0, 0)
      } else {
        let payments = &borrow_global_mut<Data>(account).payments;
        let payment = Vector::borrow(payments, Option::extract<u64>(&mut index));
        return (payment.type, payment.payee, payment.end_epoch, payment.amt)
      }
    }

    //////////////////////
    // Private function //
    //////////////////////

    // Retuns the index of the desired payment and an immutable reference to it
    // This is used often as a helper function to check existence of payments
    fun find(account: address, uid: u64): Option<u64> acquires Data {
      let payments = &borrow_global<Data>(account).payments;
      let len = Vector::length(payments);
      let i = 0;
      while (i < len) {
        let payment = Vector::borrow<Payment>(payments, i);
        if (payment.uid == uid) {
          return Option::some<u64>(i)
        };
        i = i + 1;
      };
      Option::none<u64>()
    }
  }
}

  //   // This function is only called by LibraBlock anytime the block number is changed
  //   // This architecture avoids a cyclical dependency by using the Observer design pattern
  //   public fun update_block(height: u64) acquires AccountList {
  //     // If 0x0 is updating the block number, update it for the module in AccountList
  //     Transaction::assert(Transaction::sender() == 0x0, 8001);
  //     borrow_global_mut<AccountList>(0x0).current_block = height;
  //   }


  //   // // This is currently used only for testing purposes
  //   // // TODO: Remove this function eventually
  //   // public fun make_dummy_payment_vec(payee: address): vector<Payment> {
  //   //   let ret = Vector::empty<Payment>();
  //   //   Vector::push_back(&mut ret, Payment {
  //   //       enabled: true,
  //   //       name: 0,
  //   //       uid: 0,
  //   //       payee: payee,
  //   //       end: 5,
  //   //       amount: 1,
  //   //       currency_code: Libra::currency_code<GAS::T>(),
  //   //       from_earmarked_transactions: true,
  //   //       last_block_paid: 0,
  //   //     } 
  //   //   );
  //   //   ret
  //   // }

  //   // Any account can check for the existence of a payment for any other account.
  //   // Example use case: Landlord wants to confirm that a renter still has their autopay
  //   // payments enabled and wants to check details using the payment uid that the renter
  //   // provided
  //   public fun exists(account: address, uid: u64): bool acquires Data {
  //     let index = find(account, uid);
  //     if (Option::is_some<u64>(&index)) {
  //       return true
  //     } else {
  //       return false
  //     }
  //   }