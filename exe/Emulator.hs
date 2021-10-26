{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

import           Control.Monad          hiding (fmap)
import qualified Data.ByteString.Char8  as C
import           Data.Default           (Default (..))
import qualified Data.Map               as Map
import qualified Data.Text              as Text
import           Fracada.Offchain
import           Fracada.Validator
import           Ledger.Ada             as Ada
import           Ledger.CardanoWallet   as CW
import           Ledger.Crypto          (PrivateKey)
import           Ledger.Value           as Value
import           Plutus.Trace.Emulator  as Emulator
import           PlutusTx.Prelude       hiding (Semigroup (..), unless)
import           Prelude                (IO, putStrLn, show, (<>))
import           Text.Printf            (printf)
import           Wallet.Emulator.Wallet

nftCurrency :: CurrencySymbol
nftCurrency = "66"

nftName :: TokenName
nftName = "NFT"

nft :: AssetClass
nft = AssetClass (nftCurrency, nftName)

nft2 :: AssetClass
nft2 = assetClass "bb7cd5359aa4de1dc9725fb7d8283922185d1cdbfe5fdf35df46c028" "NFT2"

w1:: MockWallet
w1 = CW.knownWallet 1
w2:: MockWallet
w2 = CW.knownWallet 2
w3:: MockWallet
w3 = CW.knownWallet 3

wallets :: [MockWallet]
wallets = [w1,w2,w3]

privKeys :: [PrivateKey]
privKeys = map CW.privateKey wallets

minSigs :: Integer
minSigs = 2

contractParams :: FractionNFTParameters
contractParams =  FractionNFTParameters {
      initTokenClass  = nft,
      authorizedPubKeys = map CW.pubKey [w1,w2,w3],
      minSigRequired   = minSigs
    }

main :: IO ()
main = do
    runEmulatorTraceIO' def emCfg scenario1
    runEmulatorTraceIO' def emCfg scenario2

emCfg :: EmulatorConfig
emCfg = EmulatorConfig (Left $ Map.fromList [(toMockWallet w, v) | w <- [w1, w2, w3]]) def def
    where
        v = Ada.lovelaceValueOf 1000_000_000 <> assetClassValue nft 1  <> assetClassValue nft2 1

-- lock and unlock
scenario1 :: EmulatorTrace ()
scenario1 = do
    h1 <- activateContractWallet (toMockWallet w1) $ endpoints contractParams
    void $ Emulator.waitNSlots 1
    let
        toFraction = ToFraction { fractions = 10, fractionTokenName = tokenName "Frac" }

    callEndpoint @"fractionNFT" h1 toFraction
    void $ Emulator.waitNSlots 1

    callEndpoint @"returnNFT" h1 ()
    void $ Emulator.waitNSlots 1

-- lock, add tokens, and unlock
scenario2 :: EmulatorTrace ()
scenario2 = do
    h1 <- activateContractWallet (toMockWallet w1) $ endpoints contractParams
    void $ Emulator.waitNSlots 1
    let
        toFraction = ToFraction { fractions = 10, fractionTokenName = tokenName "Frac" }
        -- message = Message $ encodeUtf8 $ Text.pack "bb7cd5359aa4de1dc9725fb7d8283922185d1cdbfe5fdf35df46c028.NFT2"
        message = Message  "bb7cd5359aa4de1dc9725fb7d8283922185d1cdbfe5fdf35df46c028.NFT2"
        (Message bsMsg) = message
        msgHash = hashMessage message
        sigs = map (sign msgHash) privKeys
        newToken = AddNFT { an_asset= nft2, an_sigs= sigs, an_msg= bsMsg}
        mintMore = MintMore { mm_count= 20, mm_sigs= sigs, mm_msg= bsMsg}

    -- callEndpoint @"lockNFT" h1 nft
    callEndpoint @"fractionNFT" h1 toFraction
    void $ Emulator.waitNSlots 1

    callEndpoint @"addNFT" h1 newToken
    void $ Emulator.waitNSlots 1

    callEndpoint @"mintMoreTokens" h1 mintMore
    void $ Emulator.waitNSlots 1

    callEndpoint @"returnNFT" h1 ()
    -- void $ Emulator.waitNSlots 1
