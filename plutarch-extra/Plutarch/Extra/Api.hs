module Plutarch.Extra.Api (
  getContinuingOutputs,
  findOwnInput,
  findDatum,
) where

import Plutarch.Api.V1 (
  PAddress,
  PDatum,
  PDatumHash,
  PScriptContext (PScriptContext),
  PScriptPurpose (PSpending),
  PTuple,
  PTxInInfo (PTxInInfo),
  PTxInfo (PTxInfo),
  PTxOut,
  PTxOutRef (PTxOutRef),
 )
import Plutarch.Prelude

import Plutarch.Extra.Monad (tlet, tmatch)

{- | gets a list of continuing outputs by finding
 - its own input and  returning a list of outputs with the same outAddress
-}
getContinuingOutputs :: Term s (PScriptContext :--> PBuiltinList PTxOut)
getContinuingOutputs = phoistAcyclic $
  plam $ \sc -> unTermCont $ do
    txinfo <- tlet $ pfield @"txInfo" # sc
    outs <- tlet $ pfield @"outputs" # txinfo
    tmatch (findOwnInput # sc) >>= \case
      PJust te -> do
        resolved <- tlet $ pfield @"resolved" # te
        outAdr <- tlet $ pfield @"address" # resolved
        pure $ pfilter # (matches # outAdr) #$ pmap # plam pfromData # outs
      PNothing ->
        pure $ ptraceError "can't get any continuing outputs"
  where
    matches :: Term s (PAddress :--> PTxOut :--> PBool)
    matches = phoistAcyclic $
      plam $ \adr txOut -> unTermCont $ do
        outAdr <- tlet $ pfield @"address" # txOut
        pure $ adr #== outAdr

{- | tries to finds the transaction's input
 - by looking for a txininfo in the inputs coresponding to the TxOutRef which the script purpose is spending
-}
findOwnInput :: Term s (PScriptContext :--> PMaybe PTxInInfo)
findOwnInput = phoistAcyclic $
  plam $ \sc -> unTermCont $ do
    PScriptContext te <- tmatch sc
    tmatch (pfromData $ pfield @"purpose" # te) >>= \case
      PSpending outRef' -> do
        outRef <- tlet $ pfield @"_0" # outRef'
        PTxInfo txinfo <- tmatch $ pfield @"txInfo" # te
        is <- tlet $ pmap # plam pfromData #$ pfromData $ pfield @"inputs" # txinfo
        pure $ pfind # (matches # outRef) # is
      _ ->
        pure $ pcon PNothing
  where
    matches :: Term s (PTxOutRef :--> PTxInInfo :--> PBool)
    matches = phoistAcyclic $
      plam $ \outref txininfo -> unTermCont $ do
        PTxOutRef outref' <- tmatch outref
        outRefId <- tlet $ pfield @"id" # outref'
        PTxInInfo txininfo' <- tmatch txininfo
        PTxOutRef inOutRef <- tmatch $ pfield @"outRef" # txininfo'
        inOutRefId <- tlet $ pfield @"id" # inOutRef
        pure $
          outRefId #== inOutRefId

-- | Looks up a datum by it's hash from the PTxInfo
findDatum :: Term s (PDatumHash :--> PTxInfo :--> PMaybe PDatum)
findDatum = phoistAcyclic $
  plam $ \dh txinfo -> unTermCont $ do
    txInfoData <- tlet $ pfield @"data" # txinfo
    maybeEnt <- tlet $ pfind # (matches # dh) # txInfoData
    pure $
      pmatch maybeEnt $ \case
        PNothing -> pcon PNothing
        PJust x -> pcon $ PJust $ pfromData $ pfield @"_1" # x
  where
    matches :: Term s (PDatumHash :--> PAsData (PTuple PDatumHash PDatum) :--> PBool)
    matches = phoistAcyclic $
      plam $ \dh dataTupe -> unTermCont $ do
        tupe <- tlet $ pfromData dataTupe
        pure $
          dh #== pfromData (pfield @"_0" # tupe)