module marketplace::marketplace {
    use sui::sui::SUI;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use std::string::{Self, String};
    use sui::transfer::{Self};
    use sui::url::{Self, Url};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    #[test_only]
    use sui::test_utils::assert_eq;

    /// No AdminCapability
    const ENoAdminCapability: u64 = 1;
    /// No LicenceCapability
    const ENoLicenceCapability: u64 = 2;
    /// Invalid total given
    const EInvalidTotalGiven: u64 = 3;
    /// Invalid total given
    const EInvalidListPriceGiven: u64 = 4;
    /// No licences available
    const ENoAvailableLicences: u64 = 5;
    /// Insufficient funds
    const EInsufficientFunds: u64 = 6;
    /// Nothing to update
    const ENothingToUpdate: u64 = 7;
    /// Asset is not listed for sale
    const EAssetNotListed: u64 = 8;

    /// An asset with its name, description, url, total 
    struct Asset has key {
        // Unique ID for object
        id: UID,
        // Name for asset
        name: String,
        // Description for asset
        description: String,
        // URL for asset
        url: Url,
        // List price in MIST
        list_price: u64,
        // Total of licences available
        total: u64,
        // Number of available licences, initially this is equal to `total`
        available: u64,
        // Is the asset listed
        listed: bool,
        // Sales of licences
        balance: Balance<SUI>,
        // Category
        category: u8,
    }

    struct AdminCapability has key {
        id: UID,
        // An ID for the asset that this capability controls
        asset: ID,
    }

    struct LicenceCapability has key {
        id: UID,
        // An ID for the asset 
        asset: ID,
    }

    struct AssetMinted has copy, drop {
        // Identifier for Asset minted
        id: ID,
        // Category
        category: u8,
        // The recipient of the `AdminCapability` for the asset
        recipient: address,
    }

    struct AssetUpdated has copy, drop {
        // Identifier of Asset updated
        id: ID,
        // Updated listed value
        listed: bool
    }

    struct AssetWithdrawl has copy, drop {
        // Identifier of Asset updated
        id: ID,
        // Amount transferred to recipient
        amount: u64,
        // Address of recipient
        recipient: address,
    }

    struct LicenceMinted has copy, drop {
        // Identifier of Licence minted
        id: ID,
        // Recipient of licence
        recipient: address,
    }

    struct LicenceTransferred has copy, drop {
        // Licence transferred
        id: ID,
        recipient: address,
    }

    public entry fun mint_asset(name: vector<u8>, 
                                description: vector<u8>, 
                                url: vector<u8>,
                                list_price: u64,
                                total: u64,
                                listed: bool,
                                recipient: address,
                                category: u8,
                                context: &mut TxContext) {

        assert!(total > 0, EInvalidTotalGiven);
        assert!(list_price > 0, EInvalidListPriceGiven);
        
        let asset = Asset {
            id: object::new(context),
            name: string::utf8(name),
            description: string::utf8(description),
            url: url::new_unsafe_from_bytes(url),
            total,
            available: total,
            list_price,
            balance: balance::zero(),
            listed,
            category
        };
        
        transfer::transfer(AdminCapability {
            id: object::new(context),
            asset: sui::object::id(&asset),
        }, recipient);

        event::emit(AssetMinted { 
            id: sui::object::id(&asset), 
            category, 
            recipient }
        );

        transfer::share_object(asset)
    }
    
    /// Update the listing property of the `Asset`
    public entry fun update_asset(asset: &mut Asset, admin_cap: &AdminCapability, listed: bool) {
        assert!(has_admin_caps(asset, admin_cap), ENoAdminCapability);
        assert!(listed != asset.listed, ENothingToUpdate);

        asset.listed = listed;

        event::emit(AssetUpdated {
            id: sui::object::id(asset),
            listed
        })
    }

    /// Withdraw all sales of asset to `recipient`
    /// The total amount accrued is transferred to `recipient` from the sales of licences of the Asset
    public entry fun withdraw(asset: &mut Asset, admin_cap: &AdminCapability, recipient: address, ctx: &mut TxContext) {
        assert!(has_admin_caps(asset, admin_cap), ENoAdminCapability);
        let total = balance::value(&asset.balance);
        let total_coins = coin::take(&mut asset.balance, total, ctx);

        transfer::public_transfer(total_coins, recipient);
        
        event::emit(AssetWithdrawl {
            id: sui::object::id(asset),
            amount: total, 
            recipient
        })
    }

    /// Transfer LicenceCapabiltiy to `recipient`
    /// This allows the owner of the Licence to freely transfer it to another address
    public entry fun transfer_licence_caps(asset: &Asset, licence_cap: LicenceCapability, recipient: address) {
        assert!(has_licence_caps(asset, &licence_cap), ENoLicenceCapability);
        
        event::emit(LicenceTransferred {
            id: sui::object::id(&licence_cap),
            recipient,
        });

        transfer::transfer(licence_cap, recipient);
    }

    /// Mint licence for asset sending payment, the recipient would receive a `LicenceCapability`
    public entry fun mint_licence(asset: &mut Asset, payment: &mut Coin<SUI>, recipient: address, ctx: &mut TxContext) {
        assert!(asset.listed, EAssetNotListed);
        assert!(asset.available > 0, ENoAvailableLicences);
        assert!(asset.list_price <= coin::value(payment), EInsufficientFunds);
        
        // Take payment and transfer
        let coin_balance = coin::balance_mut(payment);
        let paid = balance::split(coin_balance, asset.list_price);
        balance::join(&mut asset.balance, paid);

        asset.available = asset.available - 1;
        
        let licence_cap = LicenceCapability {
            id: object::new(ctx),
            asset: sui::object::id(asset),
        };

        event::emit(LicenceMinted { 
            id: sui::object::id(&licence_cap),
            recipient 
        });
        
        transfer::transfer(licence_cap, recipient)
    }

    /// Validate if this is the AdminCapability for Asset
    fun has_admin_caps(asset: &Asset, admin_cap: &AdminCapability) : bool {
        admin_cap.asset == sui::object::id(asset)
    }

    /// Validate if this is a LicenceCapability for Asset
    fun has_licence_caps(asset: &Asset, licence_cap: &LicenceCapability) : bool {
        licence_cap.asset == sui::object::id(asset)
    }

    #[test]
    public fun test_mint_asset() {
        use sui::test_scenario;
        let admin = @0xCAFE;
        let total = 10;
        let list_price = 100;

        let scenario_val = test_scenario::begin(admin);
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        // Check Asset is created and we as `admin` have `AdminCapability`
        test_scenario::next_tx(scenario, admin);
        {
            // Check that we have this now
            let asset = test_scenario::take_shared<Asset>(scenario);
            test_scenario::return_shared(asset);
            // Check that we have AdminCapability
            let admin_cap = test_scenario::take_from_sender<AdminCapability>(scenario);
            test_scenario::return_to_sender(scenario, admin_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInvalidTotalGiven)]
    public fun test_invalid_total_mint_asset() {
        use sui::test_scenario;
        let admin = @0xCAFE;
        let total = 0;
        let list_price = 100;

        let scenario_val = test_scenario::begin(admin);
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInvalidListPriceGiven)]
    public fun test_invalid_list_price_mint_asset() {
        use sui::test_scenario;
        let admin = @0xCAFE;
        let total = 100;
        let list_price = 0;

        let scenario_val = test_scenario::begin(admin);
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        test_scenario::end(scenario_val);
    }
    
    #[test]
    public fun test_update_asset() {
        use sui::test_scenario;
        let admin = @0xCAFE;
        let total = 100;
        let list_price = 10;
        let listed = false;

        let scenario_val = test_scenario::begin(admin);
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                listed, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        // Check that we can update the asset listed property
        test_scenario::next_tx(scenario, admin);
        {
            let asset = test_scenario::take_shared<Asset>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCapability>(scenario);
            update_asset(&mut asset, &admin_cap, !listed);
            assert!(asset.listed != listed, 0);
            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(asset);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = ENothingToUpdate)]
    public fun test_update_asset_nothing_to_update() {
        use sui::test_scenario;
        let admin = @0xCAFE;
        let total = 100;
        let list_price = 10;
        let listed = false;

        let scenario_val = test_scenario::begin(admin);
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                listed, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        // Check that we can update the asset listed property
        test_scenario::next_tx(scenario, admin);
        {
            let asset = test_scenario::take_shared<Asset>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCapability>(scenario);
            update_asset(&mut asset, &admin_cap, listed);
            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(asset);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_mint_licence() {
        // Create a licence with relevant details
        use sui::test_scenario;
        let admin = @0x1234;
        let recipient = @0xCAFE;
        let new_recipient = @0xABCD;

        let scenario_val = test_scenario::begin(admin);
        let total = 100;
        let list_price = 10;
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        test_scenario::next_tx(scenario, recipient);
        {
            // Get shared licence and check initial state
            let asset = test_scenario::take_shared<Asset>(scenario);
            assert_eq(asset.available , total);
            assert_eq(balance::value(&asset.balance), 0);

            // Mint a licence for the recipient
            let payment = coin::mint_for_testing<SUI>(list_price, test_scenario::ctx(scenario));
            mint_licence(&mut asset, &mut payment, recipient, test_scenario::ctx(scenario));
            
            // Check that have accounted for this new capability in the licence
            assert_eq(asset.available, total - 1);
            assert_eq(balance::value(&asset.balance), list_price);
            
            // Clean up
            coin::burn_for_testing(payment);
            test_scenario::return_shared(asset);
        };
        test_scenario::next_tx(scenario, recipient);
        {
            let asset = test_scenario::take_shared<Asset>(scenario);
            // Check that we have created the LicenceCapability for recipient
            let licence_cap = test_scenario::take_from_sender<LicenceCapability>(scenario);
            // Transfer LicenceCapability to new_recipient
            transfer_licence_caps(&asset, licence_cap, new_recipient);
            test_scenario::return_shared(asset);
        };
        // Check that the new address has the LicenceCapability
        test_scenario::next_tx(scenario, new_recipient);
        {
            // Check that we have created the LicenceCapability for new_recipient
            let licence_cap = test_scenario::take_from_sender<LicenceCapability>(scenario);
            test_scenario::return_to_sender(scenario, licence_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInsufficientFunds)]
    public fun test_mint_licence_invalid_payment() {
        // Create a licence with relevant details
        use sui::test_scenario;
        let admin = @0x1234;
        let recipient = @0xCAFE;
        
        let scenario_val = test_scenario::begin(admin);
        let total = 100;
        let list_price = 10;
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        test_scenario::next_tx(scenario, recipient);
        {
            // Get shared licence and check initial state
            let asset = test_scenario::take_shared<Asset>(scenario);
            // Mint a licence for the recipient
            let payment = coin::mint_for_testing<SUI>(0, test_scenario::ctx(scenario));
            mint_licence(&mut asset, &mut payment, recipient, test_scenario::ctx(scenario));
            // Clean up
            coin::burn_for_testing(payment);
            test_scenario::return_shared(asset);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = ENoAvailableLicences)]
    public fun test_mint_licence_insufficient_licences() {
        // Create a licence with relevant details
        use sui::test_scenario;
        let admin = @0x1234;
        let recipient = @0xCAFE;
        
        let scenario_val = test_scenario::begin(admin);
        let total = 1;
        let list_price = 10;
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        // Mint the only available licence
        test_scenario::next_tx(scenario, recipient);
        {
            // Get shared licence and check initial state
            let asset = test_scenario::take_shared<Asset>(scenario);
            // Mint a licence for the recipient
            let payment = coin::mint_for_testing<SUI>(list_price, test_scenario::ctx(scenario));
            mint_licence(&mut asset, &mut payment, recipient, test_scenario::ctx(scenario));
            // Clean up
            coin::burn_for_testing(payment);
            test_scenario::return_shared(asset);
        };
        // Try to mint another licence, this will fail
        test_scenario::next_tx(scenario, recipient);
        {
            // Get shared licence and check initial state
            let asset = test_scenario::take_shared<Asset>(scenario);
            // Mint a licence for the recipient
            let payment = coin::mint_for_testing<SUI>(total, test_scenario::ctx(scenario));
            mint_licence(&mut asset, &mut payment, recipient, test_scenario::ctx(scenario));
            // Clean up
            coin::burn_for_testing(payment);
            test_scenario::return_shared(asset);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EAssetNotListed)]
    public fun test_mint_licence_not_listed() {
        // Create a licence with relevant details
        use sui::test_scenario;
        let admin = @0x1234;
        let recipient = @0xCAFE;
        
        let scenario_val = test_scenario::begin(admin);
        let total = 100;
        let list_price = 10;
        let listed = false;
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                listed, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        // Mint the only available licence
        test_scenario::next_tx(scenario, recipient);
        {
            // Get shared licence and check initial state
            let asset = test_scenario::take_shared<Asset>(scenario);
            // Mint a licence for the recipient
            let payment = coin::mint_for_testing<SUI>(list_price, test_scenario::ctx(scenario));
            mint_licence(&mut asset, &mut payment, recipient, test_scenario::ctx(scenario));
            // Clean up
            coin::burn_for_testing(payment);
            test_scenario::return_shared(asset);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_withdraw_sales() {
        // Create a licence with relevant details
        use sui::test_scenario;
        let admin = @0x1234;
        let recipient = @0xCAFE;
        
        let scenario_val = test_scenario::begin(admin);
        let total = 100;
        let list_price = 10;
        // Create an asset
        let scenario = &mut scenario_val;
        {
            mint_asset(
                b"Mona Lisa", 
                b"Some famous lady", 
                b"", 
                list_price, 
                total,
                true, 
                admin, 
                1,
                test_scenario::ctx(scenario)
            );
        };
        // Purchase licence at list_price
        test_scenario::next_tx(scenario, recipient);
        {
            // Get shared licence and check initial state
            let asset = test_scenario::take_shared<Asset>(scenario);
            // Mint a licence for the recipient
            let payment = coin::mint_for_testing<SUI>(list_price, test_scenario::ctx(scenario));
            mint_licence(&mut asset, &mut payment, recipient, test_scenario::ctx(scenario));
            // Clean up
            coin::burn_for_testing(payment);
            test_scenario::return_shared(asset);
        };
        // Withdraw profits
        test_scenario::next_tx(scenario, admin);
        {
            let asset = test_scenario::take_shared<Asset>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCapability>(scenario);
            withdraw(&mut asset, &admin_cap, admin, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, admin_cap);    
            test_scenario::return_shared(asset);
        };
        // Check that admin now has the profit
        test_scenario::next_tx(scenario, admin);
        {
            let asset = test_scenario::take_shared<Asset>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCapability>(scenario);
            let coins = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            let coin_balance = coin::balance(&coins);
            assert_eq(balance::value(coin_balance), list_price);
            test_scenario::return_to_sender(scenario, coins);
            test_scenario::return_to_sender(scenario, admin_cap);    
            test_scenario::return_shared(asset);
        };
        test_scenario::end(scenario_val);
    }
}