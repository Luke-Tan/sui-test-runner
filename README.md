# Licence Marketplace Specification

### Introduction

Create a marketplace to facilitate the creation, buying and selling of licences for the use of an asset.  An asset would fall under one of the predetermined categories and the creator of the asset would be able to sell licences to this asset.  It is planned to build the frontend with Next.js which would interact with one smart contract on the Sui network.

### Features

- Authentication with zkLogin [zkLogin](https://sui.io/zklogin)
- Minting asset
    - Users can create an asset with which they can mint a number of licences
        - During the process of creating the asset they can define metadata as:
            - Name
            - Description
            - URL of asset
            - List price
            - Total available
            - Listed
            - Category
- Listing asset to be licensed
    - A user at any point in time can list or remove from listing their asset for licensing
    - When listing a user would specify the category they would want to be listed under
    - A user can buy the licence at the list price
    - A licence can be transferred freely between two parties
    - A licence would be visible in the user’s wallet
    - The asset would be visible in the creator’s wallet
- Search assets
    - A user would be able to filter the assets listed by category
- Categories
    - These would be defined by the frontend and no limitation are set at the contract level except by the data type of `u8`

### Smart Contract Implementation

We would define an asset as something similar to:

```rust
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
	// Number of free licences, initially this is equal to `total`
	free: u64,
	// Is the asset listed
	listed: bool,
	// Sales of licences
	balance: Balance<SUI>,
	// Category
	category: u8,
}
```

On minting we store `Asset` as a `SharedObject` and a `AdminCapability` object is created which is transferred to the creator.  This capability would gate access to the `SharedObject` to the creator.

An asset would be created with this entry function:

```rust
public entry fun mint_asset(name: vector<u8>,
			description: vector<u8>,
			url: vector<u8>,
			list_price: u64,
			total: u64,
			listed: bool,
			recipient: address,
			category: u8,
			context: &mut TxContext)
```

Basic checks would be made on the validity of the parameters, a `SharedObject` would be created, a `AssetMinted` event would be emitted, and a `AdminCapability` would be transferred to the `recipient`

```rust
struct AssetMinted has copy, drop {
	// Identifier for Asset minted
	id: ID,
	// Category
	category: u8,
	// The recipient of the `AdminCapability` for the asset
	recipient: address,
}

struct AdminCapability has key {
	id: UID,
	// An ID for the asset that this capability controls
	asset: ID,
}
```

In order to add or remove from listing the following entry function would be used:

```rust
public entry fun update_asset(asset: &mut Asset, admin_cap: &AdminCapability, listed: bool)
```

On change this would emit the following event:

```rust
struct AssetUpdated has copy, drop {
	// Identifier of Asset updated
	id: ID,
	// Updated listed value
	listed: bool
}
```

In order for the creator to withdraw profits made on the sale of licences for the asset:

```rust
// Withdraw all sales of asset to `recipient`
public entry fun withdraw(asset: &mut Asset, admin_cap: &AdminCapability, recipient: address, ctx: &mut TxContext)
```

Which would emit the following event:

```rust
struct AssetWithdrawl has copy, drop {
	// Identifier of Asset updated
	id: ID,
	// Amount transferred to recipient
	amount: u64,
	// Address of recipient
	recipient: address,
}
```

In order to buy a licence we would use the following:

```rust
public entry fun mint_licence(asset: &mut Asset, 
				payment: &mut Coin<SUI>,
				recipient: address,
				ctx: &mut TxContext)
```

Payment would be taken and the coins moved to `Asset.balance`, a free slot would be consumed `Asset.free - 1`, a `LicenceMinted` would be emitted and a `LicenceCapability` is transferred to the `recipient`

```rust
struct LicenceMinted has copy, drop {
	// Identifier of Licence minted
	id: ID,
	// Recipient of licence
	recipient: address,
}

struct LicenceCapability has key {
	id: UID,
	licence: ID,
}
```

Once acquired a `LicenceCapability` a user would be able to transfer it with the following entry function:

```rust
public entry fun transfer_licence_caps(asset: &Asset, 
					licence_cap: LicenceCapability,
					recipient: address)
```

This would emit the following event:

```rust
struct LicenceTransferred has copy, drop {
	// Licence transferred
	id: ID,
	recipient: address,
}
```

The following would be a list of potential error codes:

```rust
/// No AdminCapability
const ENoAdminCapability: u64 = 1;
/// No LicenceCapability
const ENoLicenceCapability: u64 = 2;
/// Invalid total given
const EInvalidTotalGiven: u64 = 3;
/// Invalid list price given
const EInvalidListPriceGiven: u64 = 4;
/// No licences available
const ENoFreeLicences: u64 = 5;
/// Insufficient funds
const EInsufficientFunds: u64 = 6;
/// Nothing to update
const ENothingToUpdate: u64 = 7;
/// Asset is not listed for sale
const EAssetNotListed: u64 = 8;
```

It is expected that a database would track the events emitted to build a table of assets that are listed with the `AssetMinted` and `AssetUpdated` events.  Both `AdminCapability` and `LicenceCapability` would be stored to the user’s wallet and would be visible there.

Additional work could be done to implement [Sui Object Display | Sui Documentation](https://docs.sui.io/standards/display) to enhance the user’s experience of the assets in their wallet but this is not part of this MVP.
