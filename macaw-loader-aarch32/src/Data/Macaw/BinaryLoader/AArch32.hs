{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Data.Macaw.BinaryLoader.AArch32 (
  AArch32LoadException(..)
  ) where

import qualified Control.Monad.Catch as X
import qualified Data.ElfEdit as EE
import qualified Data.Foldable as F
import qualified Data.List.NonEmpty as DLN
import qualified Data.Macaw.BinaryLoader as MBL
import qualified Data.Macaw.Memory as MM
import qualified Data.Macaw.Memory.ElfLoader as EL
import qualified Data.Macaw.Memory.LoadCommon as LC
import           Data.Maybe ( mapMaybe )

import qualified Data.Macaw.ARM as MA

data AArch32ElfData =
  AArch32ElfData { elf :: EE.Elf 32
                 , memSymbols :: [EL.MemSymbol 32]
                 }

instance MBL.BinaryLoader MA.ARM (EE.Elf 32) where
  type ArchBinaryData MA.ARM (EE.Elf 32) = ()
  type BinaryFormatData MA.ARM (EE.Elf 32) = AArch32ElfData
  type Diagnostic MA.ARM (EE.Elf 32) = EL.MemLoadWarning
  loadBinary = loadAArch32Binary
  entryPoints = aarch32EntryPoints

aarch32EntryPoints :: (X.MonadThrow m)
                   => MBL.LoadedBinary MA.ARM (EE.Elf 32)
                   -> m (DLN.NonEmpty (MM.MemSegmentOff 32))
aarch32EntryPoints loadedBinary =
  case MM.asSegmentOff mem addr of
    Nothing -> X.throwM (InvalidEntryPoint addr)
    Just entryPoint ->
      return (entryPoint DLN.:| mapMaybe (MM.asSegmentOff mem) symbols)
  where
    mem = MBL.memoryImage loadedBinary
    addr = MM.absoluteAddr (MM.memWord (fromIntegral (EE.elfEntry (elf (MBL.binaryFormatData loadedBinary)))))
    elfData = elf (MBL.binaryFormatData loadedBinary)
    symbols = [ MM.absoluteAddr (MM.memWord (fromIntegral (EE.steValue entry)))
              | st <- EE.elfSymtab elfData
              , entry <- F.toList (EE.elfSymbolTableEntries st)
              , EE.steType entry == EE.STT_FUNC
              ]

loadAArch32Binary :: (X.MonadThrow m)
                  => LC.LoadOptions
                  -> EE.Elf 32
                  -> m (MBL.LoadedBinary MA.ARM (EE.Elf 32))
loadAArch32Binary lopts e =
  case EL.memoryForElf lopts e of
    Left err -> X.throwM (AArch32ElfLoadError err)
    Right (mem, symbols, warnings, _) ->
      return MBL.LoadedBinary { MBL.memoryImage = mem
                              , MBL.memoryEndianness = MM.LittleEndian
                              , MBL.archBinaryData = ()
                              , MBL.binaryFormatData =
                                AArch32ElfData { elf = e
                                               , memSymbols = symbols
                                               }
                              , MBL.loadDiagnostics = warnings
                              , MBL.binaryRepr = MBL.Elf32Repr
                              }

data AArch32LoadException = AArch32ElfLoadError String
                          | forall w . (MM.MemWidth w) => InvalidEntryPoint (MM.MemAddr w)

deriving instance Show AArch32LoadException

instance X.Exception AArch32LoadException
